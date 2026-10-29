# frozen_string_literal: true

require "uri"

module Nokodown
  # Finds blocks of teasers for other pages of the site (related, latest,
  # popular, "more news") on a page that has content of its own. A teaser
  # block is an unbroken run of items of the same shape, each a card leading
  # to a different page of the same site, with a thumbnail, a date or a short
  # excerpt, under a title of its own in any language. Class names do not
  # matter: Boilerplate has already removed the blocks named "related".
  #
  # On listings, archives and hubs teasers are the content, so a block only
  # goes when its items are pages like this one (the same path but for its
  # last segment, with the same query keys) and a line of the page's own
  # text comes before it, or, on a page that declares itself an article, a
  # product or a thread, when it has a title of its own and the page keeps a
  # body of text, or a list of its own, that outweighs the titled blocks.
  #
  # Blocks are found once the content is located, but only dropped from it
  # once it is cleaned, so they weigh in pruning as before.
  class Teasers
    # kinds: how each target is kin to this page; bare: each item is a link
    # and nothing else.
    Run = Struct.new(:parent, :items, :targets, :kinds, :chars, :bare)
    # alike: the items are pages like this one; named: posts under the root
    # named by their titles, as this one is; below: pages under it.
    Block = Struct.new(:nodes, :title, :alike, :named, :below, :chars, :bare)
    # An item with its headings and the keys of the links in them.
    Card = Struct.new(:node, :headings, :title_links)

    MIN_ITEMS = 3
    MAX_ITEM_CHARS = 400
    DISTINCT_SHARE = 0.8
    RICH_SHARE = 0.5
    RICH_TEXT = 10
    SIBLING_SHARE = 0.6
    # What a block may hold besides its items and title: a "more" link.
    SLACK = 40
    # Longer text between two items is not a separator ("|", "·").
    SEPARATOR = 2
    MAX_TITLE = 60
    MAX_HEADING = 100
    MIN_BODY = 200
    DOMINANT_SHARE = 0.4
    MIN_TEXT_BEFORE = 60
    DATA_COLUMNS = 4
    CONTROLS = "select, input"
    CONTROL_TAGS = %w[form select option button].freeze
    CONTROL_LABEL = /[:：]\z/.freeze
    LETTER = /\p{L}/.freeze
    WIDE = /[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}]/.freeze
    # Shorter links name options of this page ("XL", "60x110") or menu
    # entries, not other pages' titles.
    MIN_BARE_LABEL = 15
    MIN_SECTIONS = 3
    MIN_WORDS_LEFT = 20
    BODIES = %i[article product forum qa].freeze
    PROTECTED = "h1, main, [role=main], [itemprop~=articleBody]"
    HEADING = "h1, h2, h3, h4, h5, h6, [role=heading]"
    MEDIA = "img, picture, time"
    KEPT = "h1, img, picture, video, audio, iframe, object, embed, table, pre, math"
    STRUCTURE = "ul, ol, dl, table, li, p + p"
    DATE = %r{\d{1,4}[./-]\d{1,2}[./-]\d{1,4}}.freeze
    # A line ending a sentence is the content's, not a title over a block.
    SENTENCE = /[^.][.!?]\z|[。！？؟।]\z/.freeze
    # Chinese and Japanese are written without spaces, so each Han or kana
    # character counts as a word.
    WORD = /[\p{Han}\p{Hiragana}\p{Katakana}]|[[\p{L}\p{N}]&&[^\p{Han}\p{Hiragana}\p{Katakana}]]+/.freeze
    # Query values that differ between pages of one kind are ids; "lvl=categ_see"
    # and "lvl=notice_display" are two kinds of page.
    ID_VALUE = /\d/.freeze
    DIGITS = /\A\d+\z/.freeze
    # A post's title: "andrea-jeremiah-latest-photos", "kak_sdelat_ramku.html".
    SLUG = /\A[\p{L}\p{N}%]+(?:[-_][\p{L}\p{N}%]+){2,}(?:\.[a-z]+)?\z/i.freeze
    EXTENSION = /\.[a-z]+\z/i.freeze
    DIGIT = /\d/.freeze
    # The root, a language's root ("/en/", "/pt-br/") or its index file.
    HOME = %r{\A/*(?:[a-z]{2}(?:[-_][a-z]{2})?/*)?(?:index\.\w+)?\z}i.freeze
    FILE = /\.(?:jpe?g|png|gif|webp|avif|svg|pdf|zip|docx?|xlsx?|pptx?|mp[34])\z/i.freeze

    # Keys survive the copy article cleaning works on. Content that would be
    # left with a heading and a line or two keeps its blocks: on a listing
    # whose address looks like a single page's, they were the content after
    # all.
    def self.strip(nodes, keys)
      return nodes if keys.empty?

      found = []
      nodes.each { |root| root.traverse { |node| found << node if node.element? && keys.include?(Dom.key(node)) } }
      found.reject! { |node| node.ancestors.any? { |ancestor| ancestor.element? && keys.include?(Dom.key(ancestor)) } }
      left = nodes.sum { |root| words(root) } - found.sum { |node| words(node) }
      return nodes if left < MIN_WORDS_LEFT

      parents = found.map(&:parent)
      found.each(&:remove)
      roots = nodes.map { |root| Dom.key(root) }
      parents.each { |parent| remove_emptied(parent, roots) }
      nodes
    end

    # A heading over several blocks ("Previous matches" over a column per
    # team) is left with nothing under it.
    def self.remove_emptied(node, roots)
      while node&.element? && !roots.include?(Dom.key(node)) && words(node).zero? && !node.at_css(KEPT)
        parent = node.parent
        node.remove
        node = parent
      end
    end
    private_class_method :remove_emptied

    # Words outside headings.
    def self.words(node)
      return node.content.scan(WORD).size if node.text?
      return 0 if !node.element? || Dom.heading?(node) || node["role"] == "heading"

      node.children.sum { |child| words(child) }
    end
    private_class_method :words

    # Only a page that declares itself an article, a product or a thread has
    # a body that titled boxes of teasers stand beside; on others (landing
    # pages, topics, catalogs) such boxes are often its sections.
    def initialize(body, url, urls, page_type)
      @body = body
      @urls = urls
      @page = parse(urls.resolve(url)) if url
      @url_words = UrlWords.new(url)
      @declared = BODIES.include?(page_type)
      @discussion = ContentLocator::DISCUSSIONS.include?(page_type)
    end

    # The keys of the blocks to drop and of their titles.
    def call
      return Set.new if @page.nil? || home?

      @stats = Stats.new(@body)
      @total = @stats.chars(@body)
      @blocks = blocks
      hub = sections
      @own_text = @stats.text_chars(@body) - @blocks.sum { |block| text_of(block) }
      listing = listing?
      @blocks.each_with_object(Set.new) do |block, keys|
        next if hub.include?(Dom.key(block.nodes.first)) || !removable?(block, listing)

        (block.nodes + [block.title]).compact.each { |node| keys << Dom.key(node) unless Dom.in_code?(node) }
      end
    end

    private

    # A site's home page is made of teasers.
    def home?
      @page.path.to_s.match?(HOME) && !@page.query.to_s.include?("=")
    end

    # The slides of a carousel are runs of one block.
    def blocks
      found = runs.map { |run| block(run) }.group_by { |block| block.nodes.map { |node| Dom.key(node) } }
      found.values.map do |same|
        first = same.first
        Block.new(first.nodes, first.title, same.all?(&:alike), same.all?(&:named), same.any?(&:below),
                  same.sum(&:chars), same.all?(&:bare))
      end
    end

    # Text of the page's own that outweighs a titled box, as an article does
    # each of its sidebars; a hub of titled sections has a line of intro at
    # most.
    def body_beside?(block)
      @own_text >= MIN_BODY && @own_text >= block.chars
    end

    # Titled blocks built alike, one after another, are the sections of a
    # hub ("Audio", "Cameras", "Laptops"), not boxes beside its content.
    def sections
      groups = @blocks.select(&:title).group_by { |block| shape_of(block.nodes.first) }.values
      groups.select { |group| group.size >= MIN_SECTIONS }.flatten.map { |block| Dom.key(block.nodes.first) }.to_set
    end

    # A listing's own list outweighs the titled boxes beside it.
    def listing?
      list = @blocks.select { |block| own_list?(block) && !block.alike }.max_by(&:chars)
      list && list.chars >= @blocks.sum(&:chars) - list.chars
    end

    # A list with no title of its own, under the page's H1, or under a title
    # the page's address names ("/maglia-jarrod-bowen" over "Maglia Jarrod
    # Bowen").
    def own_list?(block)
      title = block.title
      title.nil? || title.name == "h1" || !title.at_css("h1").nil? || @url_words.same_name?(Dom.text(title))
    end

    # Links to pages below this one are its own sections, and attachments are
    # part of the post that holds them.
    def removable?(block, listing)
      return false if block.below || in_post?(block) || block.nodes.any? { |node| protected?(node) }
      return false if block.bare && !list_title?(block.title)
      return false if own_list?(block) && !(block.title.nil? && block.alike && after_text?(block))
      return true if related_title?(block.title) && !dominant?(block)
      return false if block.bare && listing
      return text_before(block) >= MIN_TEXT_BEFORE if block.alike
      return true if block.named && named_beside?(block)

      !block.bare && @declared && !dominant?(block) && (listing || body_beside?(block))
    end

    # Posts are named by their titles under the root of many sites, and so
    # are a shop's pages of products and of categories. A box of them stands
    # beside a post under a heading of its own, or below a body of text on a
    # page that declares itself an article, a product or a thread.
    def named_beside?(block)
      before = text_before(block)
      (heading?(block.title) && before >= MIN_TEXT_BEFORE) || (@declared && before >= MIN_BODY)
    end

    # "Related posts", "Похожие товары", "猜你喜欢": a box that says it holds
    # other pages goes on any page, unless it holds most of it.
    def related_title?(title)
      !title.nil? && Dom.text(title).match?(Patterns::RELATED_TITLE)
    end

    # A list of bare links needs a heading or a label of its own over it: the
    # first entry of a menu can pass for a label too.
    def list_title?(title)
      return false if title.nil?

      heading?(title) || (title.name != "a" && title.at_css("a[href]").nil?)
    end

    # Not matches?, which Nokolexbor runs over the whole document.
    def protected?(node)
      main = %w[h1 main].include?(node.name) || node["role"] == "main"
      main || node["itemprop"].to_s.split.include?("articleBody") || !node.at_css(PROTECTED).nil?
    end

    # A post's body and its parent, which also holds its attachments.
    def in_post?(block)
      return false unless @discussion

      @posts ||= @body.css("[#{PostAttribution::AUTHOR}]").flat_map { |body| [Dom.key(body), Dom.key(body.parent)] }
      block.nodes.first.ancestors.any? { |ancestor| ancestor.element? && @posts.include?(Dom.key(ancestor)) }
    end

    def dominant?(block)
      block.chars >= @total * DOMINANT_SHARE
    end

    # The page's own text before the block. Keys number elements in
    # document order.
    def text_before(block)
      first = block.nodes.first
      text = 0
      first.ancestors.to_a.unshift(first).each do |node|
        break if !node.element? || node.name == "body"

        sibling = node.previous_element
        while sibling
          text += @stats.text_chars(sibling)
          sibling = sibling.previous_element
        end
      end
      earlier = @blocks.select { |other| Dom.key(other.nodes.last).to_i < Dom.key(first).to_i }
      text - earlier.sum { |other| text_of(other) }
    end

    def text_of(block)
      block.nodes.sum { |node| @stats.text_chars(node) }
    end

    # Pages like this one listed under its text in the same container, as a
    # news site lists its other stories below the story.
    def after_text?(block)
      return false if block.nodes.size == 1

      before = 0
      node = block.nodes.first.previous_element
      while node && before < MIN_BODY
        before += @stats.text_chars(node)
        node = node.previous_element
      end
      before >= MIN_BODY
    end

    # Columns of a layout can pass for teasers too, so a run holding another
    # one is the layout around it, but not one holding a card's list of bare
    # links. Children come before their parents.
    def runs
      found = []
      holding = Set.new
      @body.traverse do |node|
        next if !node.element? || node.name == "body"

        children = node.element_children
        if children.any? { |child| holding.include?(Dom.key(child)) }
          holding << Dom.key(node)
          next
        end
        next if children.size < MIN_ITEMS

        here = shapes(node).filter_map { |items| run(node, items) }
        found.concat(here)
        holding << Dom.key(node) unless here.all?(&:bare)
      end
      found
    end

    # Children of the same tag and first class, in unbroken runs: text
    # between two of them, as between the figures of an article, ends a run.
    # A heading ends it only before an item with no text, such as a
    # screenshot under its step; cards go on under the headings of a column
    # of widgets. A class no sibling shares marks a position ("first",
    # "primeiro"), not another kind of item.
    def shapes(parent)
      counts = parent.element_children.map { |child| shape_of(child) }.tally
      open = {}
      done = []
      texts = headings = 0
      parent.children.each do |child|
        if child.element?
          shape = counts[shape_of(child)] == 1 ? "#{child.name}." : shape_of(child)
          text = @stats.chars(child) > SEPARATOR
          items, seen_texts, seen_headings = open[shape]
          if items.nil? || seen_texts < texts || (seen_headings < headings && !text)
            done << items if items
            items = []
          end
          items << child
          if text && heading_line?(child)
            headings += 1
          elsif text
            texts += 1
          end
          open[shape] = [items, texts, headings]
        elsif child.text? && Dom.char_count(child.content) > SEPARATOR
          texts += 1
        end
      end
      done + open.values.map(&:first)
    end

    def heading_line?(node)
      return true if Dom.heading?(node) || node["role"] == "heading"

      inner = node.element_children
      inner.size == 1 && Dom.heading?(inner.first)
    end

    def shape_of(node)
      "#{node.name}.#{node["class"].to_s[/\S+/].to_s.delete("0-9")}"
    end

    def run(parent, items)
      return if items.size < MIN_ITEMS || data_rows?(items.first)

      chars = items.sum { |item| @stats.chars(item) }
      return if chars > MAX_ITEM_CHARS * items.size

      cards = items.map { |item| card(item) }
      links = primary_links(cards)
      return if links.nil?

      rich = rich?(cards, links)
      return unless rich || bare?(parent, cards, links)

      # Resolving every link is the costly part, so it waits for the shape.
      targets = links.map { |link| link && target(link["href"]) }
      return unless distinct_targets?(targets.compact, items.size)

      kinds = targets.compact.map { |uri| kinship(uri) }
      return Run.new(parent, items, targets, kinds, chars, false) if rich

      Run.new(parent, items, targets, kinds, chars, true) if alike?(kinds, items.size) || named?(kinds, items.size)
    end

    # Items that are each a link and nothing else, as in a "See also" list,
    # not links in a line of text.
    def bare?(parent, cards, links)
      return false if in_text?(parent)

      labels = cards.zip(links).map do |card, link|
        label = link && Dom.text(link)
        return false if label.to_s.empty? || Dom.text(card.node).sub(label, "").match?(LETTER)

        label
      end
      labels.sum { |label| width(label) } >= MIN_BARE_LABEL * labels.size
    end

    # A flat list can hold thousands of items and many runs, so each parent
    # is read once.
    def in_text?(parent)
      @in_text ||= {}
      key = Dom.key(parent)
      return @in_text[key] if @in_text.key?(key)

      @in_text[key] = parent.children.any? { |child| child.text? && !Dom.squish(child.content).empty? }
    end

    # A CJK character says about as much as a short word.
    def width(text)
      text.length + text.scan(WIDE).size * 2
    end

    # Rows under a header row, or of four or more columns, are records
    # (versions, holdings), not cards.
    def data_rows?(item)
      return false unless item.name == "tr"

      table = Dom.ancestors_named(item, "table").first
      item.css("td, th").size >= DATA_COLUMNS || !table&.at_css("thead, th").nil?
    end

    def card(item)
      headings = item.css(HEADING)
      title_links = headings.flat_map { |heading| heading.css("a[href]").map { |link| Dom.key(link) } }.to_set
      Card.new(item, headings, title_links)
    end

    # Most items of a list have a link: gives up once more than a fifth have
    # none.
    def primary_links(cards)
      allowed = cards.size * (1 - DISTINCT_SHARE)
      missing = 0
      cards.map do |card|
        link = primary_link(card)
        missing += 1 unless link
        return nil if missing > allowed

        link
      end
    end

    # Gives up once fewer than half the items can be teasers.
    def rich?(cards, links)
      allowed = cards.size * (1 - RICH_SHARE)
      misses = 0
      cards.zip(links).each do |card, link|
        misses += 1 unless teaser?(card, link)
        return false if misses > allowed
      end
      true
    end

    def distinct_targets?(targets, size)
      targets.size >= size * DISTINCT_SHARE && targets.map(&:to_s).uniq.size >= targets.size * DISTINCT_SHARE
    end

    # The title link, or else the first link with text: an image link often
    # comes first. An empty link that opens the card is stretched over it.
    def primary_link(card)
      return card.node if card.node.name == "a"

      links = card.node.css("a[href]")
      title = links.find { |link| heading_link?(link, card) } unless card.headings.empty?
      title ||= links.first if links.first && cover?(links.first)
      title || links.find { |link| @stats.chars(link) > 1 } || links.first
    end

    def title_link?(link, card)
      heading_link?(link, card) || cover?(link)
    end

    def heading_link?(link, card)
      card.title_links.include?(Dom.key(link)) || !link.at_css(HEADING).nil?
    end

    # An empty link that a stylesheet stretches over the whole card links its
    # title too.
    def cover?(link)
      @stats.chars(link).zero? && link.at_css(MEDIA).nil?
    end

    # A teaser shows a thumbnail or a date, or is a card: its title is a
    # heading link or the whole item is the link. A link in a line of text
    # ("Load data with batch jobs") is a list in the prose, a card whose
    # heading is not its link is content with a call to action ("Deposit ...
    # More →"), and a column of links is a menu.
    def teaser?(card, link)
      item = card.node
      return false if link.nil? || (!card.headings.empty? && !title_link?(link, card))
      return true if item.at_css(MEDIA)

      whole = Dom.key(link) == Dom.key(item) || cover?(link)
      return false unless whole || !card.headings.empty? || Dom.text(item).match?(DATE)

      beside_title(card, whole) >= RICH_TEXT
    end

    # Text besides the title: a card link holds all of it.
    def beside_title(card, whole)
      return @stats.text_chars(card.node) unless whole
      return 0 if card.headings.empty?

      @stats.chars(card.node) - card.headings.sum { |heading| @stats.chars(heading) }
    end

    # Another page of this site, not a file on it, nor a post further down
    # this one ("viewtopic.php?p=12#p12").
    def target(href)
      href = href.to_s.strip
      return if href.empty? || href.start_with?("#")

      uri = parse(@urls.resolve(href))
      return unless uri && host(uri) == host(@page) && !uri.path.match?(FILE)
      return if uri.path.chomp("/") == @page.path.chomp("/") && (uri.query == @page.query || anchor?(uri.fragment))

      uri.fragment = nil
      uri
    end

    # A post's anchor carries its number ("p12", "post-12"); "#a" or
    # "#comments" can be on every page of a site.
    def anchor?(fragment)
      return false unless fragment.to_s.match?(/\d/)

      @anchors ||= @body.css("[id], a[name]").flat_map { |node| [node["id"], node["name"]] }.compact.to_set
      @anchors.include?(fragment)
    end

    # The run's container, widened to wrappers holding nothing else but a
    # title and a "more" link. When the items sit beside other content, the
    # block is the items alone.
    def block(run)
      title = title_in(run.parent, run) unless holds_more?(run.parent, run, MAX_HEADING)
      nodes, title = holds_more?(run.parent, run, length(title)) ? [run.items, nil] : widen(run, title)
      title ||= title_before(nodes.first)
      size = run.items.size
      kinds = run.kinds
      alike = alike?(kinds, size)
      below = run.targets.compact.count { |uri| child?(uri) } >= size * SIBLING_SHARE
      Block.new(nodes, title, alike, !alike && named?(kinds, size), below, run.chars, run.bare)
    end

    # Looking for a title only where even the longest one would leave no
    # more than the slack.
    def widen(run, title)
      node = run.parent
      loop do
        up = node.parent
        break if up.nil? || !up.element? || up.name == "body"
        break if holds_more?(up, run, MAX_HEADING) || protected?(up)

        up_title = title || title_in(up, run)
        break if holds_more?(up, run, length(up_title))

        node = up
        title = up_title
      end
      [[node], title]
    end

    def holds_more?(node, run, title_length)
      @stats.chars(node) - run.chars - title_length > SLACK
    end

    def length(title)
      title ? @stats.chars(title) : 0
    end

    # The first title before the items, however deep: old layouts put it in
    # the first row of a table around them. Nokolexbor's css("*") is over ten
    # times slower than this XPath, which walks in the same order.
    def title_in(node, run)
      items = run.items.map { |item| Dom.key(item) }.to_set
      node.xpath(".//*").each do |descendant|
        return nil if items.include?(Dom.key(descendant))
        return descendant if title?(descendant)
      end
      nil
    end

    # Only an element right before the block, with no text between them.
    def title_before(node)
      previous = node.previous_sibling
      previous = previous.previous_sibling while previous && blank?(previous)
      previous if previous&.element? && title?(previous)
    end

    def blank?(node)
      node.element? ? @stats.chars(node).zero? && !node.at_css(MEDIA) : Dom.squish(node.content).empty?
    end

    # A heading, or a short line such as a widget's "Novinky", which may link
    # to the section it comes from. Counts ("Showing 1-12 of 40") and arrows
    # ("<") are not titles, a link among others is not, and neither is the
    # caption or the header row of a data table, which names its columns.
    def title?(node)
      return false if @stats.chars(node).zero? || @stats.chars(node) > MAX_HEADING

      text = Dom.text(node)
      return false if text.match?(/\d/) || !text.match?(/\p{L}/)
      return false if node.name == "a" || Dom.ancestors_named(node, "a").any?

      (heading?(node) ? text.length <= MAX_HEADING : label?(node, text)) && !in_data_table?(node)
    end

    def label?(node, text)
      return false if text.length > MAX_TITLE || text.match?(SENTENCE) || node.at_css(STRUCTURE) || control?(node)

      links = node.css("a[href]")
      links.empty? || (links.size == 1 && Dom.text(links.first) == text)
    end

    # A sort or filter control, its options, or its label ("Sort by:") name
    # the control, not the list below it.
    def control?(node)
      return true if CONTROL_TAGS.include?(node.name) || node.at_css(CONTROLS)
      return true if Dom.ancestors_named(node, *CONTROL_TAGS).any?

      Dom.text(node).match?(CONTROL_LABEL) && !node.parent&.at_css(CONTROLS).nil?
    end

    def in_data_table?(node)
      Dom.ancestors_named(node, "table").any? { |table| Tables.data_table?(table) }
    end

    def heading?(node)
      return true if Dom.heading?(node) || node["role"] == "heading"

      node.css(HEADING).any? { |heading| Dom.text(heading) == Dom.text(node) }
    end

    def alike?(kinds, size)
      kinds.count(:sibling) >= size * SIBLING_SHARE
    end

    def named?(kinds, size)
      kinds.count { |kind| %i[sibling named].include?(kind) } >= size * SIBLING_SHARE
    end

    def child?(uri)
      page = page_segments
      other = segments(uri)
      other.size > page.size && other.first(page.size) == page
    end

    # A page like this one: the same script with other ids for the same
    # query keys, or the same path but for the last segment and the same
    # query keys. "viewforum.php?f=2" lists the threads at "viewtopic.php?t=7".
    def kinship(uri)
      page = page_segments
      other = segments(uri)
      return unless query_keys(uri) == page_keys
      return (:sibling if same_kind?(uri)) if page == other
      return (:sibling if other.size == page.size && folders(page) == folders(other)) if page.size > 1
      return unless page.size == 1 && other.size == 1
      return :sibling if skeleton(page.first) == skeleton(other.first)

      :named if page.first.match?(SLUG) && other.first.match?(SLUG) && same_code?(page.first, other.first)
    end

    # A shop codes its kinds of page in the last part of their names: a
    # category's "-g8893.html" or "_c890317" beside a product's "-37209.html"
    # or "_p9367731".
    def same_code?(page, other)
      codes = [page, other].map { |name| decode(name).sub(EXTENSION, "").split(/[-_]/).last.to_s }
      return true unless codes.all? { |code| code.match?(DIGIT) }

      codes.map { |code| code.gsub(/\d+/, "0") }.uniq.size == 1
    end

    def decode(segment)
      URI.decode_www_form_component(segment).scrub("")
    rescue ArgumentError
      segment
    end

    # Dated permalinks differ in their date folders ("/2023/4/30/news/").
    def folders(segments)
      segments[0..-2].map { |segment| segment.match?(DIGITS) ? "0" : segment }
    end

    def same_kind?(uri)
      own = @page_params ||= params(@page).to_h
      other = params(uri)
      !other.empty? && other.all? { |key, value| value == own[key] || (id?(value) && id?(own[key])) }
    end

    # "%20" in "key=Hardware%20--%20Catalogs" is no id.
    def id?(value)
      decode(value.to_s).match?(ID_VALUE)
    end

    def segments(uri)
      uri.path.to_s.split("/").reject(&:empty?)
    end

    def page_segments
      @page_segments ||= segments(@page)
    end

    def query_keys(uri)
      params(uri).map(&:first).sort
    end

    def page_keys
      @page_keys ||= query_keys(@page)
    end

    def params(uri)
      pairs = uri.query.to_s.split("&").map do |pair|
        key, value = pair.split("=", 2)
        [key.to_s, value.to_s]
      end
      pairs.reject { |key, _| key.empty? }
    end

    # Pages directly under the root share their first word and their form:
    # "prod-123.html" and "prod-456.html", or "fq146100.html" and
    # "fq074100.html".
    def skeleton(segment)
      [segment[/\A[^-_.\d]*/], segment.gsub(/\d+/, "0").gsub(/[^\W\d_]+/, "a")]
    end

    def host(uri)
      uri.host.to_s.downcase.sub(/\A(?:www\d?|m)\./, "")
    end

    def parse(url)
      uri = URI.parse(url.to_s)
      uri if uri.is_a?(URI::HTTP) && uri.host
    rescue URI::Error, ArgumentError
      nil
    end
  end
end

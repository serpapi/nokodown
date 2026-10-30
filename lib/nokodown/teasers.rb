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
    Run = Struct.new(:parent, :items, :targets, :chars)
    # alike: the items are pages like this one; below: pages under it.
    Block = Struct.new(:nodes, :title, :alike, :below, :chars)
    # An item with its headings and the keys of the links in them.
    Card = Struct.new(:node, :headings, :title_links)
    # A wrapper, the keys of its elements walked so far, those left as a
    # stack, and the title the walk stopped at.
    Walk = Struct.new(:node, :passed, :stack, :title)

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
    # The root, a language's root ("/en/", "/pt-br/") or its index file.
    HOME = %r{\A/*(?:[a-z]{2}(?:[-_][a-z]{2})?/*)?(?:index\.\w+)?\z}i.freeze
    FILE = /\.(?:jpe?g|png|gif|webp|avif|svg|pdf|zip|docx?|xlsx?|pptx?|mp[34])\z/i.freeze
    # A pager's links name page numbers ("1 2 4 5").
    PAGE_NUMBER = /\A\d{1,4}\z/.freeze
    MIN_PAGES = 2

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
      worded = {}
      parents.each { |parent| remove_emptied(parent, roots, worded) }
      nodes
    end

    # A heading over several blocks ("Previous matches" over a column per
    # team) is left with nothing under it. Removing an element without
    # words leaves the words of the others as they were, so a parent found
    # to have some is not read again for the next block removed from it.
    def self.remove_emptied(node, roots, worded)
      while node&.element? && !roots.include?(Dom.key(node)) && !worded?(node, worded) && !node.at_css(KEPT)
        parent = node.parent
        node.remove
        node = parent
      end
    end
    private_class_method :remove_emptied

    # By key, told apart from the parser's copies of a misnested <font>,
    # which share its attributes.
    def self.worded?(node, worded)
      same = worded[Dom.key(node)] ||= []
      return true if same.any? { |other| other == node }
      return false unless any_words?(node)

      same << node
      true
    end
    private_class_method :worded?

    # Whether words(node) is above zero, stopping at the first word.
    def self.any_words?(node)
      return node.content.match?(WORD) if node.text?
      return false if !node.element? || Dom.heading?(node) || node["role"] == "heading"

      child = node.child
      while child
        return true if any_words?(child)

        child = child.next_sibling
      end
      false
    end
    private_class_method :any_words?

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
      body = body?
      @blocks.each_with_object(Set.new) do |block, keys|
        next if hub.include?(Dom.key(block.nodes.first)) || !removable?(block, body)

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
        Block.new(first.nodes, first.title, same.all?(&:alike), same.any?(&:below), same.sum(&:chars))
      end
    end

    # Text of the page's own that outweighs the titled boxes, as an article
    # does its sidebars; a hub of titled sections has a line of intro at most.
    def body?
      own_text = @stats.text_chars(@body) - @blocks.sum { |block| text_of(block) }
      boxes = @blocks.select { |block| block.title && !block.alike }.sum(&:chars)
      (own_text >= MIN_BODY && own_text >= boxes) || listing?
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

    # A list with no title of its own, or under the page's H1.
    def own_list?(block)
      block.title.nil? || block.title.name == "h1" || !block.title.at_css("h1").nil?
    end

    # Links to pages below this one are its own sections, and attachments are
    # part of the post that holds them. A section that the page's own table
    # of contents lists is part of the page whatever it holds, such as the
    # rows of an item's recipes, each a link to another item.
    def removable?(block, body)
      return false if block.below || in_post?(block) || block.nodes.any? { |node| protected?(node) }
      return false if pager?(block)
      return false if InPageLinks.listed?(block.nodes.first)
      return false if own_list?(block) && !(block.title.nil? && block.alike && after_text?(block))
      return text_before(block) >= MIN_TEXT_BEFORE if block.alike

      @declared && body && !dominant?(block)
    end

    # A block holding the pager to this page's other pages ("1 2 4 5" to
    # "list-catid-139257_--p2.html" from "..._--p3.html") is the listing
    # itself, its title the column's: a box of teasers beside the content
    # does not page through the page it is on.
    def pager?(block)
      pages = 0
      block.nodes.each do |node|
        node.css("a[href]").each do |link|
          number = Dom.text(link)
          next unless number.match?(PAGE_NUMBER)

          uri = target(link["href"])
          pages += 1 if uri && page_of_this?(uri, number)
          return true if pages >= MIN_PAGES
        end
      end
      false
    end

    # This page's address with the link's number in place of one of its
    # own ("--p3" to "--p2"), or added to its query ("?cat=5&page=2"). A
    # view count linking to another coded page ("459" to "/93319.html") is
    # not.
    def page_of_this?(uri, number)
      own = address(@page)
      other = address(uri)
      if own.gsub(/\d+/, "0") == other.gsub(/\d+/, "0")
        changed = own.scan(/\d+/).zip(other.scan(/\d+/)).reject { |mine, theirs| mine == theirs }
        return changed.size == 1 && changed.first.last.to_i == number.to_i
      end
      added = params(uri) - params(@page)
      uri.path == @page.path && params(@page).all? { |pair| params(uri).include?(pair) } &&
        added.size == 1 && added.first.last == number
    end

    def address(uri)
      "#{uri.path}?#{params(uri).sort.map { |pair| pair.join("=") }.join("&")}"
    end

    # Not matches?, which Nokolexbor runs over the whole document. Widening
    # asks about the same large wrappers for every run inside them, so the
    # elements that hold a protected one are listed once.
    def protected?(node)
      main = %w[h1 main].include?(node.name) || node["role"] == "main"
      main || node["itemprop"].to_s.split.include?("articleBody") || holds_protected?(node)
    end

    def holds_protected?(node)
      key = Dom.key(node)
      return !node.at_css(PROTECTED).nil? if key.nil?

      @holders ||= protected_holders
      @holders.fetch(key, []).any? { |holder| holder == node }
    end

    # The ancestors of protected elements, by key. The parser's copies of a
    # misnested <b> or <font> share its attributes, key included, so each
    # element is told apart from its copies. A climb stops at an element
    # already listed, whose own ancestors are listed with it.
    def protected_holders
      @body.css(PROTECTED).each_with_object({}) do |found, holders|
        node = found
        while (node = node.parent)&.element?
          key = Dom.key(node)
          next if key.nil?

          same = holders[key] ||= []
          break if same.any? { |holder| holder == node }

          same << node
        end
      end
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
    # one is the layout around it. Children come before their parents.
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
        holding << Dom.key(node) unless here.empty?
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
      return if links.nil? || !rich?(cards, links)

      targets = links.map { |link| link && target(link["href"]) }
      Run.new(parent, items, targets, chars) if distinct_targets?(targets.compact, items.size)
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
    # comes first.
    def primary_link(card)
      return card.node if card.node.name == "a"

      links = card.node.css("a[href]")
      title = links.find { |link| title_link?(link, card) } unless card.headings.empty?
      title || links.find { |link| @stats.chars(link) > 1 } || links.first
    end

    def title_link?(link, card)
      card.title_links.include?(Dom.key(link)) || !link.at_css(HEADING).nil?
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

      whole = Dom.key(link) == Dom.key(item)
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
      Block.new(nodes, title, share?(run) { |uri| sibling?(uri) }, share?(run) { |uri| child?(uri) }, run.chars)
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
    # the first row of a table around them. Runs side by side widen into the
    # same wrapper, and each walked past all the runs before it, so the walk
    # of a wrapper in document order is kept and resumed: what it has passed
    # holds no title but the one it stopped at. It stops before an item, so
    # the next run still asks whether that element is a title.
    def title_in(node, run)
      items = run.items.map { |item| Dom.key(item) }.to_set
      walk = walk_of(node)
      return nil if items.any? { |key| walk.passed.include?(key) }
      return walk.title if walk.title

      until walk.stack.empty?
        descendant = walk.stack.last
        return nil if items.include?(Dom.key(descendant))

        walk.stack.pop
        walk.passed << Dom.key(descendant)
        walk.stack.concat(descendant.element_children.to_a.reverse)
        return walk.title = descendant if title?(descendant)
      end
      nil
    end

    # By key, told apart from the parser's copies of a misnested <font>,
    # which share its attributes.
    def walk_of(node)
      key = Dom.key(node)
      return new_walk(node) if key.nil?

      same = (@walks ||= {})[key] ||= []
      same.find { |walk| walk.node == node } || new_walk(node).tap { |walk| same << walk }
    end

    def new_walk(node)
      Walk.new(node, Set.new, node.element_children.to_a.reverse, nil)
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

    def share?(run, &test)
      run.targets.compact.count(&test) >= run.items.size * SIBLING_SHARE
    end

    def child?(uri)
      page = segments(@page)
      other = segments(uri)
      other.size > page.size && other.first(page.size) == page
    end

    # A page like this one: the same script with other ids for the same
    # query keys, or the same path but for the last segment and the same
    # query keys. "viewforum.php?f=2" lists the threads at "viewtopic.php?t=7".
    def sibling?(uri)
      page = segments(@page)
      other = segments(uri)
      return false unless page.size == other.size && query_keys(uri) == query_keys(@page)
      return same_kind?(uri) if page == other
      return folders(page) == folders(other) if page.size > 1

      page.size == 1 && skeleton(page.first) == skeleton(other.first)
    end

    # Dated permalinks differ in their date folders ("/2023/4/30/news/").
    def folders(segments)
      segments[0..-2].map { |segment| segment.match?(DIGITS) ? "0" : segment }
    end

    def same_kind?(uri)
      own = params(@page).to_h
      other = params(uri)
      !other.empty? && other.all? { |key, value| value == own[key] || (id?(value) && id?(own[key])) }
    end

    def id?(value)
      value.to_s.match?(ID_VALUE)
    end

    def segments(uri)
      uri.path.to_s.split("/").reject(&:empty?)
    end

    def query_keys(uri)
      params(uri).map(&:first).sort
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

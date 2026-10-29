# frozen_string_literal: true

require "uri"

module Nokodown
  # Finds blocks of teasers for other pages of the site (related, latest,
  # popular, "more news") on a page that has content of its own. A teaser
  # block is a run of items of the same shape, each a card leading to a
  # different page of the same site, with a thumbnail, a date or a short
  # excerpt, under a title of its own in any language. Class names do not
  # matter: Boilerplate has already removed the blocks named "related".
  #
  # On listings, archives and hubs teasers are the content, so a block only
  # goes when its items are pages like this one (the same path but for its
  # last segment, with the same query keys), or, on a page that declares
  # itself an article, a product or a thread, when it has a title of its own
  # and the page keeps a body of text, or a list of its own, that outweighs
  # the titled blocks.
  #
  # The page is judged whole, but the blocks found are only dropped from the
  # selected content once it is cleaned, so they weigh in locating the
  # content and in pruning as before.
  class Teasers
    Run = Struct.new(:parent, :items, :targets, :chars)
    Block = Struct.new(:nodes, :title, :siblings, :children, :chars)

    MIN_ITEMS = 3
    MAX_ITEM_CHARS = 400
    DISTINCT_SHARE = 0.8
    RICH_SHARE = 0.5
    RICH_TEXT = 10
    SIBLING_SHARE = 0.6
    # What a block may hold besides its items and title: a "more" link.
    SLACK = 40
    MAX_TITLE = 60
    MAX_HEADING = 100
    MIN_BODY = 200
    BODY_SHARE = 1.0
    DOMINANT_SHARE = 0.4
    MIN_SIBLINGS_BODY = 50
    MIN_SECTIONS = 3
    MIN_WORDS_LEFT = 20
    BODIES = %i[article product forum qa].freeze
    PROTECTED = "h1, main, [role=main], [itemprop~=articleBody]"
    HEADING = "h1, h2, h3, h4, h5, h6, [role=heading]"
    MEDIA = "img, picture, time"
    STRUCTURE = "ul, ol, dl, table, li, p + p"
    DATE = %r{\d{1,4}[./-]\d{1,2}[./-]\d{1,4}}.freeze
    # Scripts written without spaces count a word per character.
    WORD = /[\p{Han}\p{Hiragana}\p{Katakana}]|[\p{L}\p{N}]+/.freeze
    # The root, a language's root ("/en/", "/pt-br/") or its index file.
    HOME = %r{\A/*(?:[a-z]{2}(?:[-_][a-z]{2})?/*)?(?:index\.\w+)?\z}i.freeze
    FILE = /\.(?:jpe?g|png|gif|webp|avif|svg|pdf|zip|docx?|xlsx?|pptx?|mp[34])\z/i.freeze

    # Keys survive the copy article cleaning works on. Content that would be
    # left with a heading and a line or two keeps its blocks: on a listing
    # whose address looks like a single page's, they were the content after
    # all.
    def self.strip(nodes, keys)
      return nodes if keys.empty?

      found = nodes.flat_map { |root| root.css("*").select { |node| keys.include?(Dom.key(node)) } }
      found.reject! { |node| node.ancestors.any? { |ancestor| ancestor.element? && keys.include?(Dom.key(ancestor)) } }
      left = nodes.sum { |root| words(root) } - found.sum { |node| words(node) }
      found.each(&:remove) if left >= MIN_WORDS_LEFT
      nodes
    end

    # Words outside headings.
    def self.words(node)
      return 0 if Dom.heading?(node)

      node.content.scan(WORD).size - node.css(HEADING).sum { |heading| heading.content.scan(WORD).size }
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
    end

    # The keys of the blocks to drop and of their titles.
    def call
      return Set.new if @page.nil? || home?

      @stats = Stats.new(@body)
      # The slides of a carousel are runs of one block.
      blocks = runs.map { |run| block(run) }.uniq { |block| block.nodes.map { |node| Dom.key(node) } }
      own_text = @stats.text_chars(@body) - blocks.sum { |block| block.nodes.sum { |node| @stats.text_chars(node) } }
      body = body?(blocks, own_text)
      total = @stats.chars(@body)
      sections = sections(blocks)
      blocks.each_with_object(Set.new) do |block, keys|
        next if sections.include?(Dom.key(block.nodes.first)) || !removable?(block, own_text, body, total)

        (block.nodes + [block.title]).compact.each { |node| keys << Dom.key(node) unless Dom.in_code?(node) }
      end
    end

    private

    # A site's home page is made of teasers.
    def home?
      @page.path.to_s.match?(HOME) && !@page.query.to_s.include?("=")
    end

    # Text of the page's own that outweighs the titled boxes, as an article
    # does its sidebars; a hub of titled sections has a line of intro at most.
    def body?(blocks, own_text)
      boxes = blocks.select { |block| block.title && !block.siblings }.sum(&:chars)
      (own_text >= MIN_BODY && own_text >= boxes * BODY_SHARE) || listing?(blocks)
    end

    # Titled blocks built alike, one after another, are the sections of a
    # hub ("Audio", "Cameras", "Laptops"), not boxes beside its content.
    def sections(blocks)
      titled = blocks.select(&:title).group_by { |block| shape_of(block.nodes.first) }
      titled.values.select { |group| group.size >= MIN_SECTIONS }.flatten.map { |block| Dom.key(block.nodes.first) }.to_set
    end

    # A listing's own list outweighs the titled boxes beside it.
    def listing?(blocks)
      list = blocks.select { |block| own_list?(block) && !block.siblings }.max_by(&:chars)
      list && list.chars >= blocks.sum(&:chars) - list.chars
    end

    # A list with no title of its own, or under the page's H1.
    def own_list?(block)
      block.title.nil? || block.title.name == "h1" || !block.title.at_css("h1").nil?
    end

    # Links to pages below this one are its own sections.
    def removable?(block, own_text, body, total)
      return false if block.children || block.nodes.any? { |node| node.at_css(PROTECTED) }
      return block.title.nil? && block.siblings && after_text?(block) && own_text >= MIN_SIBLINGS_BODY if own_list?(block)
      return own_text >= MIN_SIBLINGS_BODY if block.siblings

      @declared && body && block.chars < total * DOMINANT_SHARE
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
    # one is the layout around it.
    def runs
      found = @body.css("*").flat_map do |parent|
        children = parent.element_children
        children.size < MIN_ITEMS ? [] : shapes(children).values.filter_map { |items| run(parent, items) }
      end
      outer = found.flat_map { |run| run.parent.ancestors.map { |ancestor| Dom.key(ancestor) } }.compact.to_set
      found.reject { |run| outer.include?(Dom.key(run.parent)) }
    end

    # Children grouped by tag and first class. A class no sibling shares
    # marks a position ("first", "primeiro"), not another kind of item.
    def shapes(children)
      named = children.map { |child| [child, shape_of(child)] }
      counts = named.map(&:last).tally
      named.group_by { |child, shape| counts[shape] > 1 ? shape : "#{child.name}." }.transform_values { |pairs| pairs.map(&:first) }
    end

    def shape_of(node)
      "#{node.name}.#{node["class"].to_s[/\S+/].to_s.delete("0-9")}"
    end

    def run(parent, items)
      return if items.size < MIN_ITEMS

      chars = items.sum { |item| @stats.chars(item) }
      return if chars > MAX_ITEM_CHARS * items.size

      links = primary_links(items)
      return if links.nil? || items.zip(links).count { |item, link| teaser?(item, link) } < items.size * RICH_SHARE

      targets = links.map { |link| link && target(link["href"]) }
      Run.new(parent, items, targets, chars) if distinct_targets?(targets.compact, items.size)
    end

    # Stops at the first items without a link, as in most lists.
    def primary_links(items)
      allowed = items.size * (1 - DISTINCT_SHARE)
      missing = 0
      items.map do |item|
        link = primary_link(item)
        missing += 1 unless link
        return nil if missing > allowed

        link
      end
    end

    def distinct_targets?(targets, size)
      targets.size >= size * DISTINCT_SHARE && targets.map(&:to_s).uniq.size >= targets.size * DISTINCT_SHARE
    end

    # The title link, or else the first link with text: an image link often
    # comes first.
    def primary_link(item)
      return item if item.name == "a"

      links = item.css("a[href]")
      headings = item.css(HEADING)
      title = links.find { |link| title_link?(link, headings) } unless headings.empty?
      title || links.find { |link| @stats.chars(link) > 1 } || links.first
    end

    def title_link?(link, headings)
      link.at_css(HEADING) || headings.any? { |heading| heading.css("a[href]").any? { |inner| Dom.key(inner) == Dom.key(link) } }
    end

    # A teaser shows a thumbnail or a date, or is a card: its title is a
    # heading link or the whole item is the link. A link in a line of text
    # ("Load data with batch jobs") is a list in the prose, a card whose
    # heading is not its link is content with a call to action ("Deposit ...
    # More →"), and a column of links is a menu.
    def teaser?(item, link)
      headings = item.css(HEADING)
      return false if link.nil? || (!headings.empty? && !title_link?(link, headings))
      return true if item.at_css(MEDIA)

      card = Dom.key(link) == Dom.key(item)
      return false unless card || !headings.empty? || Dom.text(item).match?(DATE)

      beside_title(item, card, headings) >= RICH_TEXT
    end

    # Text besides the title: a card link holds all of it.
    def beside_title(item, card, headings)
      return @stats.text_chars(item) unless card
      return 0 if headings.empty?

      @stats.chars(item) - headings.sum { |heading| @stats.chars(heading) }
    end

    # Another page of this site, not a file on it.
    def target(href)
      href = href.to_s.strip
      return if href.empty? || href.start_with?("#")

      uri = parse(@urls.resolve(href))
      return unless uri && host(uri) == host(@page) && !uri.path.match?(FILE)

      uri.fragment = nil
      uri unless uri.path.chomp("/") == @page.path.chomp("/") && uri.query == @page.query
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
        break if up.nil? || !up.element? || up.name == "body" || holds_more?(up, run, MAX_HEADING) || up.at_css(PROTECTED)

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
    # the first row of a table around them.
    def title_in(node, run)
      items = run.items.map { |item| Dom.key(item) }.to_set
      node.css("*").each do |descendant|
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
      return false if text.match?(/\d/) || !text.match?(/\p{L}/) || node.name == "a" || Dom.ancestors_named(node, "a").any?

      (heading?(node) ? text.length <= MAX_HEADING : label?(node, text)) && !in_data_table?(node)
    end

    def label?(node, text)
      return false if text.length > MAX_TITLE || node.at_css(STRUCTURE)

      links = node.css("a[href]")
      links.empty? || (links.size == 1 && Dom.text(links.first) == text)
    end

    def in_data_table?(node)
      Dom.ancestors_named(node, "table").any? { |table| Tables.data_table?(table) }
    end

    def heading?(node)
      return true if Dom.heading?(node) || node["role"] == "heading"

      node.css(HEADING).any? { |heading| Dom.text(heading) == Dom.text(node) }
    end

    def share?(run, &block)
      run.targets.compact.count(&block) >= run.items.size * SIBLING_SHARE
    end

    def child?(uri)
      page = segments(@page)
      other = segments(uri)
      other.size > page.size && other.first(page.size) == page
    end

    # A page like this one: the same script with other values for the same
    # query keys, or the same path but for the last segment and the same
    # query keys. "viewforum.php?f=2" lists the threads at "viewtopic.php?t=7".
    def sibling?(uri)
      page = segments(@page)
      other = segments(uri)
      keys = query_keys(@page)
      return false unless page.size == other.size && query_keys(uri) == keys
      return !keys.empty? if page == other
      return page[0..-2] == other[0..-2] if page.size > 1

      page.size == 1 && skeleton(page.first) == skeleton(other.first)
    end

    def segments(uri)
      uri.path.to_s.split("/").reject(&:empty?)
    end

    def query_keys(uri)
      uri.query.to_s.split("&").map { |pair| pair[/\A[^=]*/] }.reject(&:empty?).sort
    end

    # Pages directly under the root share their first word and their form:
    # "prod-123.html" and "prod-456.html".
    def skeleton(segment)
      [segment[/\A[^-_.]*/], segment.gsub(/\d+/, "0").gsub(/[^\W\d_]+/, "a")]
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

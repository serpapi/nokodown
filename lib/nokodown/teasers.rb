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
  # last segment, or the same query keys), or when the page keeps a body of
  # text, or a list of its own, that outweighs the titled blocks.
  #
  # The page is judged whole, but the blocks found are only dropped from the
  # selected content once it is cleaned, so they weigh in locating the
  # content and in pruning as before.
  class Teasers
    Run = Struct.new(:parent, :items, :targets, :chars)
    Block = Struct.new(:nodes, :title, :siblings, :chars)

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
    MIN_SIBLINGS_BODY = 50
    MIN_SECTIONS = 3
    DOMINANT_SHARE = 0.5
    PROTECTED = "h1, main, [role=main], [itemprop~=articleBody]"
    HEADING = "h1, h2, h3, h4, h5, h6, [role=heading]"
    MEDIA = "img, picture, time"
    STRUCTURE = "ul, ol, dl, table, li, p + p"
    DATE = %r{\d{1,4}[./-]\d{1,2}[./-]\d{1,4}}.freeze
    # The root, a language's root ("/en/", "/pt-br/") or its index file.
    HOME = %r{\A/*(?:[a-z]{2}(?:[-_][a-z]{2})?/*)?(?:index\.\w+)?\z}i.freeze
    FILE = /\.(?:jpe?g|png|gif|webp|avif|svg|pdf|zip|docx?|xlsx?|pptx?|mp[34])\z/i.freeze

    # Keys survive the copy article cleaning works on. A selected root that
    # is itself a teaser block stays: dropping it would leave nothing.
    def self.strip(nodes, keys)
      return nodes if keys.empty?

      nodes.each { |root| root.css("*").select { |node| keys.include?(Dom.key(node)) }.each(&:remove) }
    end

    def initialize(body, url, urls)
      @body = body
      @urls = urls
      @page = parse(urls.resolve(url)) if url
    end

    # The keys of the blocks to drop and of their titles.
    def call
      return Set.new if @page.nil? || home?

      @stats = Stats.new(@body)
      blocks = runs.map { |run| block(run) }
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

    def removable?(block, own_text, body, total)
      return false if block.nodes.any? { |node| node.at_css(PROTECTED) }
      return block.title.nil? && block.siblings && after_text?(block) && own_text >= MIN_SIBLINGS_BODY if own_list?(block)
      return own_text >= MIN_SIBLINGS_BODY if block.siblings

      body && block.chars < total * DOMINANT_SHARE
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
        shapes(parent.element_children).values.filter_map { |items| run(parent, items) }
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

      links = items.map { |item| primary_link(item) }
      targets = links.map { |link| link && target(link["href"]) }
      return unless distinct_targets?(targets.compact, items.size)
      return if items.zip(links).count { |item, link| teaser?(item, link) } < items.size * RICH_SHARE

      Run.new(parent, items, targets, chars)
    end

    def distinct_targets?(targets, size)
      targets.size >= size * DISTINCT_SHARE && targets.map(&:to_s).uniq.size >= targets.size * DISTINCT_SHARE
    end

    # The title link, or else the first link with text: an image link often
    # comes first.
    def primary_link(item)
      links = item.name == "a" ? [item] : item.css("a[href]").to_a
      links.find { |link| title_link?(link) } || links.find { |link| @stats.chars(link) > 1 } || links.first
    end

    def title_link?(link)
      link.at_css(HEADING) || Dom.ancestors_named(link, *Dom::HEADINGS).any?
    end

    # A teaser shows a thumbnail or a date, or is a card: its title is a
    # heading link or the whole item is the link. A link in a line of text
    # ("Load data with batch jobs") is a list in the prose, a card whose
    # heading is not its link is content with a call to action ("Deposit ...
    # More →"), and a column of links is a menu.
    def teaser?(item, link)
      heading = item.at_css(HEADING)
      return false if link.nil? || (heading && !title_link?(link))
      return true if item.at_css(MEDIA)

      card = Dom.key(link) == Dom.key(item)
      return false unless card || title_link?(link) || Dom.text(item).match?(DATE)

      extra = card ? @stats.chars(item) - (heading ? @stats.chars(heading) : @stats.chars(item)) : @stats.text_chars(item)
      extra >= RICH_TEXT
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
      nodes = [run.parent]
      title = title_in(run.parent, run)
      if extra(run.parent, run, title) > SLACK
        nodes = run.items
        title = nil
      else
        nodes, title = widen(run, title)
      end
      title ||= title_before(nodes.first)
      Block.new(nodes, title, siblings?(run), run.chars)
    end

    def widen(run, title)
      node = run.parent
      loop do
        up = node.parent
        break if up.nil? || !up.element? || up.name == "body" || up.at_css(PROTECTED)

        up_title = title || title_in(up, run)
        break if extra(up, run, up_title) > SLACK

        node = up
        title = up_title
      end
      [[node], title]
    end

    def extra(node, run, title)
      @stats.chars(node) - run.chars - (title ? @stats.chars(title) : 0)
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
    # to the section it comes from. Counts ("Showing 1-12 of 40") are not
    # titles, and neither is a link among others.
    def title?(node)
      text = Dom.text(node)
      return false if text.empty? || text.match?(/\d/) || node.name == "a" || Dom.ancestors_named(node, "a").any?
      return text.length <= MAX_HEADING if heading?(node)
      return false if text.length > MAX_TITLE || node.at_css(STRUCTURE)

      links = node.css("a[href]")
      links.empty? || (links.size == 1 && Dom.text(links.first) == text)
    end

    def heading?(node)
      return true if Dom.heading?(node) || node["role"] == "heading"

      node.css(HEADING).any? { |heading| Dom.text(heading) == Dom.text(node) }
    end

    def siblings?(run)
      run.targets.compact.count { |uri| sibling?(uri) } >= run.items.size * SIBLING_SHARE
    end

    # A page like this one: the same path but for the last segment, or the
    # same script with other values for the same query keys.
    def sibling?(uri)
      page = segments(@page)
      other = segments(uri)
      return false unless page.size == other.size
      return page[0..-2] == other[0..-2] if page.size > 1
      return !query_keys(uri).empty? && query_keys(uri) == query_keys(@page) if page == other

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

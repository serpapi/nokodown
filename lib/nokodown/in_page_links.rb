# frozen_string_literal: true

module Nokodown
  # Links within the page: a table of contents repeats the headings below
  # it, and "back to top" after every answer leads where the reader has
  # been. Footnotes keep their marks and back-references, which sit in text
  # of their own.
  class InPageLinks
    CONTAINERS = "ul, ol, dl, div, nav, table, td, p, section"
    MIN_ENTRIES = 3
    LINK_SHARE = 0.8
    MAX_BACK_WORDS = 4
    TOP = /\A#top\z/i.freeze
    # A link there is a title, a term or a question that opens its answer.
    TITLES = %w[h1 h2 h3 h4 h5 h6 dt th summary label].freeze
    LETTER = /\p{L}/.freeze
    WORDS = /[\p{L}\p{N}]+/.freeze
    SEPARATORS = /\A[\s\p{P}\p{S}]*\z/.freeze
    # Set on the parts of the page that its table of contents lists.
    LISTED = "data-nokodown-listed"
    LISTS = %w[ul ol nav].freeze

    # anchors: the page's ids and a[name]s, with the key of their element.
    def self.anchors(document)
      document.css("[id], a[name]").each_with_object({}) do |node, found|
        [node["id"], node["name"]].compact.each { |name| found[name] ||= Dom.key(node).to_i }
      end
    end

    # The parts of the page that a table of contents lists: three or more
    # links in one list to elements that open with a heading. Marked before
    # Boilerplate drops the list with the rest of the navigation.
    def self.mark_listed(body)
      links = body.css("a[href^='#']")
      return if links.size < MIN_ENTRIES

      ids = body.css("[id]").each_with_object({}) { |node, found| found[node["id"]] ||= node }
      parts = {}
      # Links in document order: those of one list follow one another.
      entries(links, ids).chunk_while { |(list, _), (other, _)| list == other }.each do |run|
        listed = run.map(&:last).uniq { |part| part["id"] }
        listed.each { |part| parts[part["id"]] = part } if listed.size >= MIN_ENTRIES
      end
      innermost(parts).each { |part| part[LISTED] = "" }
    end

    def self.listed?(node)
      [node, *ancestors(node)].any? { |step| step.key?(LISTED) }
    end

    # Each link to a part that opens with a heading, with the outermost list
    # around it, so a nested table of contents counts as one. A heading's
    # permalink sits inside the part it links to.
    def self.entries(links, ids)
      headed = {}
      links.filter_map do |link|
        part = ids[link["href"][1..]]
        next if part.nil? || ancestors(part).any? { |node| node == link }

        around = ancestors(link)
        list = around.select { |node| LISTS.include?(node.name) }.last
        next if list.nil? || around.any? { |node| node == part }

        [list, part] if headed.fetch(part["id"]) { headed[part["id"]] = opens_with_heading?(part) }
      end
    end

    # A part that holds another may be the main column, which a skip link
    # leads to.
    def self.innermost(parts)
      outer = Set.new
      parts.each_value { |part| ancestors(part).each { |node| outer << node["id"] if parts[node["id"]] == node } }
      parts.reject { |id, _| outer.include?(id) }.values
    end

    # Down through first elements, past empty ones such as icons; a selector
    # per part would cost more than the rest of the marking.
    def self.opens_with_heading?(part)
      heading = part
      until heading.nil? || Dom.heading?(heading)
        heading = heading.first_element_child
        heading = heading.next_element while heading && heading.first_element_child.nil? && heading.content.strip.empty?
      end
      title = heading && Dom.text(heading)
      !title.nil? && !title.empty? && Dom.text(part).start_with?(title)
    end

    # Walking up by parent is many times faster than Nokolexbor's ancestors.
    def self.ancestors(node)
      found = []
      found << node while (node = node.parent)&.element?
      found
    end
    private_class_method :entries, :innermost, :opens_with_heading?, :ancestors

    def initialize(root, anchors, urls)
      @root = root
      @anchors = anchors
      @urls = urls
      @targets = {}
    end

    # Only a container around links into the page, and around no other link,
    # can be one. Reading every container's links costs as much as its
    # subtree, so the others are ruled out by key first.
    def contents
      candidates = candidate_keys
      return [] if candidates.empty?

      tables = @root.css(CONTAINERS).select do |node|
        (Dom.key(node).nil? || candidates.include?(Dom.key(node))) && contents?(node)
      end
      keys = tables.map { |node| Dom.key(node) }.to_set
      tables.reject { |node| node.ancestors.any? { |ancestor| ancestor.element? && keys.include?(Dom.key(ancestor)) } }
    end

    def back_links
      @root.css("a[href]").select { |link| back?(link) }
    end

    private

    # Keys of the elements around a link into the page and around no other
    # link, once the page has MIN_ENTRIES links into it.
    def candidate_keys
      targets, others = @root.css("a[href]").partition { |link| target(link) }
      return Set.new if targets.size < MIN_ENTRIES

      keys_around(targets) - keys_around(others)
    end

    # Each element is added once: a walk up stops where an earlier one went.
    def keys_around(links)
      links.each_with_object(Set.new) do |link, keys|
        node = link
        while (node = node.parent)&.element?
          key = Dom.key(node)
          break unless key.nil? || keys.add?(key)
        end
      end
    end

    def contents?(node)
      links = node.css("a[href]")
      return false if links.size < MIN_ENTRIES || !links.all? { |link| target(link) }

      texts = links.map { |link| Dom.text(link) }
      texts.any? { |text| text.match?(LETTER) } && texts.sum(&:length) >= Dom.text(node).length * LINK_SHARE
    end

    # A short link alone on its line, to the top or to a point above it
    # outside the link's own section. The href rules out most links before
    # their text and ancestors are read.
    def back?(link)
      href = link["href"].strip
      return false unless href.match?(TOP) || target(link)

      text = Dom.text(link)
      return false if text.scan(WORDS).size > MAX_BACK_WORDS || !text.match?(LETTER)
      return false if Dom.ancestors_named(link, *TITLES).any?

      (href.match?(TOP) || above?(link, href)) && alone?(link, text)
    end

    # Asked only of a link into the page.
    def above?(link, href)
      position = @anchors[fragment(href)]
      position < Dom.key(link).to_i && link.ancestors.none? { |ancestor| ancestor.element? && Dom.key(ancestor).to_i == position }
    end

    def alone?(link, text)
      line = link.ancestors.find { |ancestor| Dom.block?(ancestor) }
      line.nil? || Dom.text(line).sub(text, "").match?(SEPARATORS)
    end

    # Every link is asked about, and resolving an href costs more than the
    # rest, so each href is judged once.
    def target(link)
      href = link["href"].strip
      @targets.fetch(href) { @targets[href] = into_page?(href) }
    end

    def into_page?(href)
      name = fragment(href)
      return false if name.nil? || name.empty? || !@anchors.key?(name)

      href.start_with?("#") || (@urls && @urls.same_page?(@urls.resolve(href).to_s))
    end

    def fragment(href)
      href[/#(.*)\z/, 1]
    end
  end
end

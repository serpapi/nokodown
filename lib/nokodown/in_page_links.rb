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

    # anchors: the page's ids and a[name]s, with the key of their element.
    def self.anchors(document)
      document.css("[id], a[name]").each_with_object({}) do |node, found|
        [node["id"], node["name"]].compact.each { |name| found[name] ||= Dom.key(node).to_i }
      end
    end

    def initialize(root, anchors, urls)
      @root = root
      @anchors = anchors
      @urls = urls
    end

    def contents
      tables = @root.css(CONTAINERS).select { |node| contents?(node) }
      keys = tables.map { |node| Dom.key(node) }.to_set
      tables.reject { |node| node.ancestors.any? { |ancestor| ancestor.element? && keys.include?(Dom.key(ancestor)) } }
    end

    def back_links
      @root.css("a[href]").select { |link| back?(link) }
    end

    private

    def contents?(node)
      links = node.css("a[href]")
      return false if links.size < MIN_ENTRIES || !links.all? { |link| target(link) }

      texts = links.map { |link| Dom.text(link) }
      texts.any? { |text| text.match?(LETTER) } && texts.sum(&:length) >= Dom.text(node).length * LINK_SHARE
    end

    # A short link alone on its line, to the top or to a point above it
    # outside the link's own section.
    def back?(link)
      text = Dom.text(link)
      return false if text.scan(WORDS).size > MAX_BACK_WORDS || !text.match?(LETTER)
      return false if Dom.ancestors_named(link, *TITLES).any?

      href = link["href"].strip
      (href.match?(TOP) || above?(link, href)) && alone?(link, text)
    end

    def above?(link, href)
      return false unless target(link)

      position = @anchors[fragment(href)]
      position < Dom.key(link).to_i && link.ancestors.none? { |ancestor| ancestor.element? && Dom.key(ancestor).to_i == position }
    end

    def alone?(link, text)
      line = link.ancestors.find { |ancestor| Dom.block?(ancestor) }
      line.nil? || Dom.text(line).sub(text, "").match?(SEPARATORS)
    end

    def target(link)
      href = link["href"].strip
      name = fragment(href)
      return false if name.nil? || name.empty? || !@anchors.key?(name)

      href.start_with?("#") || (@urls && @urls.same_page?(@urls.resolve(href).to_s))
    end

    def fragment(href)
      href[/#(.*)\z/, 1]
    end
  end
end

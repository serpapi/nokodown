# frozen_string_literal: true

module Nokodown
  # Character and link counts for every element under a root, computed in one
  # pass. Counts are non-whitespace characters, so indentation and line breaks
  # in the source do not skew them.
  class Stats
    FRAGMENT_LINK_WEIGHT = 0.3

    def initialize(root)
      @chars = {}
      @link_chars = {}
      measure(root, 0.0)
    end

    def chars(node)
      lookup(@chars, node)
    end

    def link_chars(node)
      lookup(@link_chars, node)
    end

    def text_chars(node)
      chars(node) - link_chars(node)
    end

    def link_density(node)
      total = chars(node)
      total.zero? ? 0.0 : link_chars(node) / total
    end

    private

    def lookup(table, node)
      key = Dom.key(node)
      measure(node, inherited_link_weight(node)) unless table.key?(key)
      table[key]
    end

    def measure(node, link_weight)
      chars = 0.0
      link_chars = 0.0
      node.children.each do |child|
        if child.text? || child.cdata?
          count = Dom.char_count(child.content)
          chars += count
          link_chars += count * link_weight
        elsif child.element?
          child_chars, child_link_chars = measure(child, link_weight_for(child, link_weight))
          chars += child_chars
          link_chars += child_link_chars
        end
      end
      store(node, chars, link_chars)
    end

    def store(node, chars, link_chars)
      key = Dom.key(node)
      if key
        @chars[key] = chars
        @link_chars[key] = link_chars
      end
      [chars, link_chars]
    end

    def link_weight_for(node, inherited)
      href = node.name == "a" && node["href"]
      return inherited unless href

      href.start_with?("#") ? FRAGMENT_LINK_WEIGHT : 1.0
    end

    def inherited_link_weight(node)
      anchor = node.ancestors.find { |ancestor| ancestor.element? && ancestor.name == "a" && ancestor["href"] }
      anchor ? link_weight_for(anchor, 0.0) : 0.0
    end
  end
end

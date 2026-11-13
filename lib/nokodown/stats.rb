# frozen_string_literal: true

module Nokodown
  # Character and link counts for every element under a root, computed in one
  # pass. Counts are non-whitespace characters, so indentation and line breaks
  # in the source do not skew them.
  class Stats
    FRAGMENT_LINK_WEIGHT = 0.3
    # What an element without a key reads as.
    UNKNOWN = [nil, nil].freeze
    # Node types, compared as integers in the hot walk.
    TEXT_NODE = Nokolexbor::Node::TEXT_NODE
    CDATA_NODE = Nokolexbor::Node::CDATA_SECTION_NODE
    ELEMENT_NODE = Nokolexbor::Node::ELEMENT_NODE

    def initialize(root)
      # [chars, link_chars] by key, so a lookup reads one entry.
      @counts = {}
      measure(root, 0.0)
    end

    def chars(node)
      counts(node)[0]
    end

    def link_chars(node)
      counts(node)[1]
    end

    def text_chars(node)
      chars, link_chars = counts(node)
      chars - link_chars
    end

    def link_density(node)
      total, link_chars = counts(node)
      total.zero? ? 0.0 : link_chars / total
    end

    private

    def counts(node)
      key = Dom.key(node)
      @counts.fetch(key) do
        measure(node, inherited_link_weight(node))
        @counts.fetch(key, UNKNOWN)
      end
    end

    def measure(node, link_weight)
      chars = 0.0
      link_chars = 0.0
      child = node.child
      while child
        type = child.type
        if type == TEXT_NODE || type == CDATA_NODE
          count = Dom.char_count(child.content)
          chars += count
          link_chars += count * link_weight
        elsif type == ELEMENT_NODE
          child_chars, child_link_chars = measure(child, link_weight_for(child, link_weight))
          chars += child_chars
          link_chars += child_link_chars
        end
        child = child.next_sibling
      end
      store(node, chars, link_chars)
    end

    def store(node, chars, link_chars)
      counts = [chars, link_chars]
      key = Dom.key(node)
      # A frozen key is stored as is; Hash would copy it.
      @counts[key.freeze] = counts if key
      counts
    end

    def link_weight_for(node, inherited)
      href = node["href"]
      return inherited unless href && node.name == "a"

      href.start_with?("#") ? FRAGMENT_LINK_WEIGHT : 1.0
    end

    def inherited_link_weight(node)
      anchor = node.ancestors.find { |ancestor| ancestor.element? && ancestor.name == "a" && ancestor["href"] }
      anchor ? link_weight_for(anchor, 0.0) : 0.0
    end
  end
end

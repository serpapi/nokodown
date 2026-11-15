# frozen_string_literal: true

module Nokodown
  # Character and link counts for every element under a root, computed in one
  # pass. Counts are non-whitespace characters, so indentation and line breaks
  # in the source do not skew them.
  class Stats
    FRAGMENT_LINK_WEIGHT = 0.3
    # Node types, compared as integers in the hot walk.
    TEXT_NODE = Nokolexbor::Node::TEXT_NODE
    CDATA_NODE = Nokolexbor::Node::CDATA_SECTION_NODE
    ELEMENT_NODE = Nokolexbor::Node::ELEMENT_NODE

    def initialize(root)
      @root = root
      measure_all
    end

    # Removes the nodes from the tree, leaving the counts a new Stats of the
    # root would make for every element still in it. Only the elements
    # around the nodes are counted again, each from its children in order,
    # so every sum adds the same numbers in the same order. The counts of
    # the removed elements stay, but no element in the tree has their keys.
    # A walk up from a removed node stops at an ancestor an earlier walk
    # cleared, as everything above it was cleared then too. The ancestor is
    # matched by node, not by key: a page can give <html> any key.
    def remove(nodes)
      cleared = {}
      nodes.each do |node|
        ancestor = node.parent
        while ancestor
          if ancestor.type == ELEMENT_NODE
            key = Dom.key(ancestor)
            break if key && cleared[key] == ancestor

            @counts.delete(key)
            cleared[key] = ancestor if key
          end
          ancestor = ancestor.parent
        end
        node.remove
      end
      # Copies of a misnested formatting element share a key, and the copy
      # measured last decides its counts; those are all measured again.
      @shared_keys ? measure_all : recount(@root, 0.0)
      self
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

    # Copies of a misnested formatting element share one attribute list,
    # and an attribute written through one copy can drop another's key. An
    # element without a key is counted each time it is asked about, as the
    # walk from the root counts it, link and all, and nothing is stored for
    # it or its descendants.
    def counts(node)
      key = Dom.key(node)
      return unstored(node, link_weight_for(node, inherited_link_weight(node))) unless key

      @counts.fetch(key) { measure(node, inherited_link_weight(node)) }
    end

    def measure_all
      # [chars, link_chars] by key, so a lookup reads one entry.
      @counts = {}
      @stored = 0
      measure(@root, 0.0)
      @shared_keys = @stored != @counts.size
      self
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

    # As measure counts node, storing nothing.
    def unstored(node, link_weight)
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
          child_chars, child_link_chars = unstored(child, link_weight_for(child, link_weight))
          chars += child_chars
          link_chars += child_link_chars
        end
        child = child.next_sibling
      end
      [chars, link_chars]
    end

    # As measure counts node, reading the counts it still has.
    def recount(node, link_weight)
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
          key = Dom.key(child)
          child_chars, child_link_chars = (key && @counts[key]) || recount(child, link_weight_for(child, link_weight))
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
      return counts unless key

      # A frozen key is stored as is; Hash would copy it.
      @counts[key.freeze] = counts
      @stored += 1
      counts
    end

    def link_weight_for(node, inherited)
      href = node["href"]
      return inherited unless href && node.name == "a"

      href.start_with?("#") ? FRAGMENT_LINK_WEIGHT : 1.0
    end

    def inherited_link_weight(node)
      ancestor = node.parent
      while ancestor
        return link_weight_for(ancestor, 0.0) if ancestor.type == ELEMENT_NODE && ancestor.name == "a" && ancestor["href"]

        ancestor = ancestor.parent
      end
      0.0
    end
  end
end

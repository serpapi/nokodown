# frozen_string_literal: true

module Nokodown
  # Character and link counts for every element under a root, computed in one
  # pass. Counts are non-whitespace characters, so indentation and line breaks
  # in the source do not skew them.
  class Stats
    FRAGMENT_LINK_WEIGHT = 0.3
    HELD = 16
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
      @recent = @places = @listed = nil
      @shared_keys ? measure_all : recount(@root, 0.0)
      self
    end

    # Writing an attribute through a copy of a misnested formatting element
    # can drop a link target as well as a key, so the elements without a key
    # are counted again when next asked.
    def forget_keyless
      @recent = @places = @listed = nil
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

    def counts(node)
      key = Dom.key(node)
      return keyless(node) unless key

      @counts.fetch(key) { measure(node, inherited_link_weight(node)) }
    end

    # Copies of a misnested formatting element share one attribute list,
    # and an attribute written through one copy can drop another's key. An
    # element without a key is counted as the walk from the root counts it,
    # link and all, and nothing is stored under a key for it. Its counts are
    # held until #remove or #forget_keyless, so asking about it again, or
    # about an element around it, does not count it again.
    #
    # Nodes cannot be hashed, so counts are held in lists and found by
    # node. An element asked about again soon is found in the list for its
    # source position, which keeps only its HELD most recently used.
    # Positions restart in every fragment the page parses (each <noscript>),
    # so elements elsewhere can push it out of that list. It is then found
    # at its place: the key of its nearest ancestor with one, how many
    # elements without a key lie between, and its position. Sibling
    # fragments, and copies of a misnested ancestor, which share its key,
    # can put any number of elements at one place, so a place lists them
    # all and pushes none out. So an element in the tree is counted once.
    # link_weight is the element's own, and key and depth its place, when
    # known.
    def keyless(node, link_weight = nil, key = nil, depth = nil)
      position = node.source_location
      recent = (@recent ||= {})[position] ||= []
      entry = held(recent, node)
      return entry[1] if entry

      key, depth = keyless_above(node) unless depth
      places = (@places ||= {})[key] ||= {}
      # Two places sharing a number would only share a list.
      list = places[(position << 32) | depth] ||= []
      entry = at_place(list, node)
      unless entry
        entry = [node, unstored(node, link_weight || link_weight_for(node, inherited_link_weight(node)), key, depth + 1)]
        list << entry
      end
      hold(recent, entry)
      entry[1]
    end

    # The entry for node in the list of its place, if held. A place lists
    # every element asked about there and pushes none out. A short list
    # keeps the most recently used last; a longer one keeps its order and
    # is searched by Listed.
    def at_place(list, node)
      if list.size <= Listed::FINE
        held(list, node)
      else
        ((@listed ||= {}.compare_by_identity)[list] ||= Listed.new(list, node.document)).find(node)
      end
    end

    # Finds an element in a long list of entries, which only grows. Elements
    # are mostly asked about in document order, one way or the other, so one
    # is first looked for beside the last one found. The entries are also
    # put in NodeSets of a COARSE and of a FINE run of them, which compare
    # nodes in C: they tell which run holds the element, and only that FINE
    # run is compared in Ruby. So no search walks the tree. A search costs
    # under a nanosecond per entry; an element not yet listed is looked for
    # in every run, so listing n elements at one place costs about n * n / 2
    # of those, a quarter of a second for 24,000.
    class Listed
      FINE = 32
      COARSE = 1024

      def initialize(entries, document)
        @entries = entries
        @document = document
        @fine = []
        @coarse = []
        @indexed = 0
        @last = 0
      end

      def find(node)
        last = @last
        index =
          if near?(last, node) then last
          elsif near?(last + 1, node) then last + 1
          elsif last.positive? && near?(last - 1, node) then last - 1
          else search(node)
          end
        return unless index

        @last = index
        @entries[index]
      end

      private

      def near?(index, node)
        entry = @entries[index]
        entry && entry[0] == node
      end

      def search(node)
        index_entries
        coarse = @coarse.index { |nodes| nodes.include?(node) }
        return unless coarse

        runs = COARSE / FINE
        fine = coarse * runs + @fine[coarse * runs, runs].index { |nodes| nodes.include?(node) }
        first = fine * FINE
        first + @entries[first, FINE].index { |other, _| other == node }
      end

      # Puts the entries listed since the last search in NodeSets.
      def index_entries
        indexed = @indexed
        while indexed < @entries.size
          @coarse << Nokolexbor::NodeSet.new(@document) if (indexed % COARSE).zero?
          @fine << Nokolexbor::NodeSet.new(@document) if (indexed % FINE).zero?
          node = @entries[indexed][0]
          @coarse.last << node
          @fine.last << node
          indexed += 1
        end
        @indexed = indexed
      end
    end

    # The entry for node, moved to the end as the most recently used.
    def held(list, node)
      index = list.rindex { |other, _| other == node }
      return unless index

      entry = list.delete_at(index)
      list << entry
      entry
    end

    def hold(list, entry)
      list.shift if list.size >= HELD
      list << entry
    end

    # The key of the nearest ancestor with one, and how many elements
    # without a key lie between.
    def keyless_above(node)
      depth = 0
      ancestor = node.parent
      while ancestor && ancestor.type == ELEMENT_NODE
        key = Dom.key(ancestor)
        return [key, depth] if key

        depth += 1
        ancestor = ancestor.parent
      end
      [nil, depth]
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

    # As measure counts node, storing nothing under a key. key and depth are
    # the place of a child without a key, when node has none either.
    def unstored(node, link_weight, key = nil, depth = nil)
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
          child_weight = link_weight_for(child, link_weight)
          child_chars, child_link_chars =
            if Dom.key(child)
              unstored(child, child_weight)
            elsif depth
              keyless(child, child_weight, key, depth)
            else
              keyless(child, child_weight, Dom.key(node), 0)
            end
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

# frozen_string_literal: true

module Nokodown
  # Sites give headings ids made from their text so tables of contents can
  # link to them ("h-what-is-social-media", "related-coverage-2"), and
  # documentation generators put the same id on the section the heading
  # opens. Such an id says what the section is about, not what kind of
  # section it is: "social" in it does not make a share bar. Marked once, so
  # every class/id rule can leave it out.
  module HeadingAnchors
    PREFIX = /\A[a-z][-_]/i.freeze
    COUNTER = /[-_]\d+\z/.freeze
    # XPath, because Lexbor's CSS engine takes longer to match a list of tag names.
    HEADINGS = ".//h1|.//h2|.//h3|.//h4|.//h5|.//h6"

    # Headings that are nothing but the name of a widget: "Feedback", "Table
    # of contents". Reviews are only removed from product pages, where a
    # section headed by them is the reviews widget, so naming them anywhere
    # will do: "Ratings and reviews".
    WIDGET_NAME = /\A(?:#{Patterns::PAGE_FURNITURE}|#{Patterns::SECONDARY})\z|#{Patterns::REVIEWS}/.freeze

    module_function

    # Reading the elements around a heading costs about as much as checking
    # eight elements for an id, so a page this dense in headings has its
    # elements checked instead.
    DENSE_HEADINGS = 8
    # Telling whether a heading opens its parent's section takes a step or
    # more. Past one step per heading and this share of the page's elements,
    # headings are taking turns between sections that open with many empty
    # elements, and every element with an id is checked instead.
    STEP_SHARE = 16

    # Only a heading, an element in one or the section one opens has a
    # label, so only the elements around headings are read, each of them
    # once: a label can be the text of a whole section, and a section can
    # hold thousands of headings. Where headings are most of the page, or
    # telling which sections they open takes long, every element with an id
    # is read instead, which marks the same elements.
    def mark(root, elements = Dom.elements(root))
      headings = root.xpath(HEADINGS)
      if headings.size * DENSE_HEADINGS <= elements.size
        headings = headings.to_a
        sections = sections(headings, root, [headings.size + elements.size / STEP_SHARE])
        return if sections && mark_around_headings(headings, sections)
      end
      elements.each { |node| mark_anchor(node) if node.key?("id") }
    end

    # A heading's parent has a label only when the heading opens its section,
    # so it is read from that heading alone, unless it is read as a heading
    # or as a heading's child already. Headings in one section mostly follow
    # each other, and one that shares the last one's parent does not open it.
    # The sections headings open are listed first, with the index of their
    # heading, so nothing is read when the steps in +left+ run out: nil then.
    # Their ids are not looked at here: a parent that headings take turns
    # with another would have its id looked up once per turn.
    def sections(headings, root, left)
      sections = []
      last = root
      headings.each_with_index do |heading, index|
        parent = heading.parent
        next if parent == last

        last = parent
        next if parent == root || !labelled_apart?(parent, root)

        opening = opening?(heading, parent, left)
        return if opening.nil?

        sections << [index, parent] if opening
      end
      sections
    end

    # Lists the elements with an id around the headings, each section after
    # its heading, then marks those that are anchors. The parser repeats an
    # element left open or closed out of order, and its copies share the
    # first one's attributes: a mark added through a later copy is lost when
    # the first one gains an attribute, so copies have to be marked in
    # document order. Where a listed element is such a later copy, which
    # takes no reading of its id, nothing is read and false is returned, so
    # every element with an id is read instead.
    def mark_around_headings(headings, sections)
      sections << [headings.size]
      at = 0
      found = []
      headings.each_with_index do |heading, index|
        mark_around(heading, found)
        next unless sections[at][0] == index

        parent = sections[at][1]
        at += 1
        found << parent if parent.key?("id")
      end
      return false if found.any? { |node| node.attribute("id").parent != node }

      found.each { |node| mark_anchor(node) }
      true
    end

    def mark_around(heading, found)
      found << heading if heading.key?("id")
      child = heading.first_element_child
      while child
        found << child if child.key?("id") && !Dom.heading?(child)
        child = child.next_element
      end
    end

    def mark_anchor(node)
      node[Dom::ANCHOR] = "1" if anchor?(node)
    end

    def labelled_apart?(section, root)
      holder = section.parent
      !Dom.heading?(section) && !(holder != root && Dom.heading?(holder))
    end

    # Whether the heading may open its parent's section: only elements
    # without child elements come before it. Whether they are empty takes
    # reading their text, so #label tells that, and only for a section with
    # an id. Stepping back from the heading passes each element once over
    # all headings. Stepping on from the first child, over text and elements
    # without any content, stops as soon as one is a heading or holds an
    # element, so a section that does not open with the heading is told at
    # once. It steps over text one node at a time, as stepping to the next
    # element would pass all of it again for every heading. Each step is
    # taken from +left+: nil when they run out.
    def opening?(heading, parent, left)
      back = heading.previous_element
      ahead = parent.child
      loop do
        return nil if (left[0] -= 1).negative?

        if ahead
          return true if ahead == heading
          return false if Dom.heading?(ahead)

          inner = ahead.element? ? ahead.child : nil
          return false if inner && (inner.element? || inner.next&.element?)

          ahead = inner ? nil : ahead.next
        end
        return true if back.nil?
        return false if Dom.heading?(back) || back.first_element_child

        back = back.previous_element
      end
    end

    def anchor?(node)
      label = label(node)
      return false if label.nil? || junk?(label)

      text = compact(label)
      !text.empty? && variants(node["id"]).any? { |variant| compact(variant) == text }
    end

    # A junk label's anchor names the widget under it, which goes too; keeping
    # the heading would leave it without a section. Only its words count: the
    # permalink the anchor markup adds ("¶", "#", a zero-width space) would
    # keep the anchored patterns from matching.
    def junk?(label)
      words = label.downcase.scan(/[\p{L}\p{N}]+/)
      phrase = words.join(" ")
      return true if phrase.match?(Patterns::NOISE_HEADING) || phrase.match?(Patterns::BOILERPLATE_TEXT)

      words.join("-").match?(WIDGET_NAME)
    end

    # The heading itself, a wiki's headline span inside it, or the heading
    # that opens a section (after any empty anchor targets).
    def label(node)
      return Dom.text(node) if Dom.heading?(node) || Dom.heading?(node.parent)

      heading = opening_heading(node)
      heading && Dom.text(heading)
    end

    def opening_heading(node)
      child = node.first_element_child
      child = child.next_element while child && !Dom.heading?(child) && empty?(child)
      child if child && Dom.heading?(child)
    end

    def empty?(node)
      node.first_element_child.nil? && node.content.strip.empty?
    end

    # A one-letter prefix ("h-", "s-") and a counter for repeated headings.
    def variants(id)
      [id, id.sub(PREFIX, "")].flat_map { |variant| [variant, variant.sub(COUNTER, "")] }
    end

    # Slugifiers differ in how they treat case, accents, apostrophes and spaces.
    def compact(string)
      string.unicode_normalize(:nfkd).downcase.gsub(/[^\p{L}\p{N}]/, "")
    end
  end
end

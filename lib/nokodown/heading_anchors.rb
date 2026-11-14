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
        return mark_around_headings(headings, sections) if sections
      end
      elements.each { |node| mark_anchor(node) if node.key?("id") }
    end

    # A heading's parent has a label only when the heading opens its section,
    # so it is read from that heading alone, unless it is read as a heading
    # or as a heading's child already. Headings in one section mostly follow
    # each other, and one that shares the last one's parent does not open it.
    # These parents are listed first, with the index of their heading and
    # whether it opens them, so nothing is read when the steps in +left+ run
    # out: nil then.
    def sections(headings, root, left)
      sections = []
      last = root
      headings.each_with_index do |heading, index|
        parent = heading.parent
        next if parent == last

        last = parent
        next if parent == root || !labelled_apart?(parent, root)

        opening = parent.key?("id") ? opening?(heading, parent, left) : :later
        return if opening.nil?

        sections << [index, parent, opening]
      end
      sections
    end

    # Marks in the order of the headings, each section after its heading:
    # a misnested element's copies share their attributes, so the id is
    # looked at again when the section is read.
    def mark_around_headings(headings, sections)
      sections << [headings.size]
      at = 0
      headings.each_with_index do |heading, index|
        mark_around(heading)
        next unless sections[at][0] == index

        _, parent, opening = sections[at]
        at += 1
        next unless parent.key?("id")

        opening = opening?(heading, parent) if opening == :later
        mark_anchor(parent) if opening
      end
    end

    def mark_around(heading)
      mark_anchor(heading) if heading.key?("id")
      child = heading.first_element_child
      while child
        mark_anchor(child) if child.key?("id") && !Dom.heading?(child)
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

    # Whether only empty elements come before the heading, as #label reads a
    # section. Stepping back from the heading reads each element once over
    # all headings. Stepping on from the first element, as far as elements
    # without any content, stops as soon as one is a heading or holds an
    # element, so a section that does not open with the heading is told at
    # once. Each step is taken from +left+: nil when they run out.
    def opening?(heading, parent, left = [Float::INFINITY])
      back = heading.previous_element
      ahead = parent.first_element_child
      loop do
        return nil if (left[0] -= 1).negative?

        if ahead
          return true if ahead == heading
          return false if Dom.heading?(ahead) || ahead.first_element_child

          ahead = ahead.child ? nil : ahead.next_element
        end
        return true if back.nil?
        return false if Dom.heading?(back) || !empty?(back)

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

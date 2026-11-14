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

    # Only a heading, an element in one or the section one opens has a
    # label, so only the elements around headings are read, each of them
    # once: a label can be the text of a whole section, and a section can
    # hold thousands of headings. Where headings are most of the page, every
    # element with an id is read instead, which marks the same elements.
    def mark(root, elements = Dom.elements(root))
      headings = root.xpath(HEADINGS)
      if headings.size * DENSE_HEADINGS > elements.size
        elements.each { |node| mark_anchor(node) if node.key?("id") }
      else
        parents = {}
        headings.to_a.each { |heading| mark_around(heading, root, parents) }
      end
    end

    def mark_around(heading, root, parents)
      mark_anchor(heading) if heading.key?("id")
      child = heading.first_element_child
      while child
        mark_anchor(child) if child.key?("id") && !Dom.heading?(child)
        child = child.next_element
      end
      parent = heading.parent
      mark_anchor(parent) if parent != root && parent.key?("id") && first_read?(parent, heading, root, parents)
    end

    def mark_anchor(node)
      node[Dom::ANCHOR] = "1" if anchor?(node)
    end

    # Past this many elements sharing an id, a parent is read from the first
    # heading in it, which is found by stepping back over its other children.
    SAME_IDS = 8

    # A parent is read once, from the first heading met in it, unless it is
    # read as a heading or as a heading's child already. Parents read are
    # listed by id, since elements are not keyed yet.
    def first_read?(parent, heading, root, parents)
      read = (parents[parent["id"]] ||= [])
      return false if read.any? { |node| node == parent }
      return first_heading?(heading) && labelled_apart?(parent, root) if read.size >= SAME_IDS

      read << parent
      labelled_apart?(parent, root)
    end

    def labelled_apart?(parent, root)
      holder = parent.parent
      !Dom.heading?(parent) && !(holder != root && Dom.heading?(holder))
    end

    def first_heading?(heading)
      before = heading.previous_element
      before = before.previous_element while before && !Dom.heading?(before)
      before.nil?
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

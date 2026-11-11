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

    # Headings that are nothing but the name of a widget: "Feedback", "Table
    # of contents". Reviews are only removed from product pages, where a
    # section headed by them is the reviews widget, so naming them anywhere
    # will do: "Ratings and reviews".
    WIDGET_NAME = /\A(?:#{Patterns::PAGE_FURNITURE}|#{Patterns::SECONDARY})\z|#{Patterns::REVIEWS}/.freeze

    module_function

    def mark(root)
      Dom.elements(root).each { |node| node[Dom::ANCHOR] = "1" if node.key?("id") && anchor?(node) }
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

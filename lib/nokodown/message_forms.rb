# frozen_string_literal: true

module Nokodown
  # Comment, review and contact forms, with the title and notes above them
  # ("Leave a Reply", "Be the first to review", "留言框") in any language.
  # Preprocessor marks them and the wrappers that add only their title while
  # their controls still say what they ask; what is left of them in the
  # content goes once it is chosen, so they never sway that choice.
  module MessageForms
    MARK = "data-nokodown-message-form"
    # An e-mail address, or a phone number of seven digits or more.
    CONTACT_DETAIL = /[^\s@]@[^\s@]|\d(?:[\s().\/-]{0,2}\d){6}/.freeze
    TITLE = 120
    TITLE_PIECES = 3
    TITLE_ELEMENTS = 30
    # Outside a heading, a line as short as "Leave a Reply" or "留言框"; a
    # longer note only under a heading. Themes set the title in a span named
    # for it ("comment-reply-title").
    TITLE_LINE = 40
    TITLE_NAME = /(?<![a-z])(?:title|heading)(?![a-z])/.freeze
    BEYOND_TITLE = Set.new(%w[img picture video iframe table ul ol dl h1]).freeze

    module_function

    # A marked wrapper holds its form, which goes with it.
    def blocks(roots)
      marked = roots.flat_map { |root| root.css("[#{MARK}]").to_a }
      keys = marked.map { |node| Dom.key(node) }.to_set
      marked.reject { |node| node.ancestors.any? { |ancestor| ancestor.element? && keys.include?(Dom.key(ancestor)) } }
    end

    # The wrappers that add only a heading and a few short lines to the form,
    # without links, pictures, tables, lists, an address or a phone number.
    # The details beside a contact form, the other tabs beside a review
    # form, or the post a reply form follows, are more. Only what the climb
    # adds is read, so a thread of reply forms is read once.
    def title_wrappers(form)
      note = { chars: 0, pieces: 0, headings: 0, elements: 0, long: 0 }
      wrappers = []
      node = form
      wrappers << (node = node.parent) while wrapper?(node.parent) && note_beside?(node, note)
      wrappers
    end

    def wrapper?(node)
      return false unless node&.element? && node.name != "body"

      !Boilerplate::CONTENT_ANCESTORS.include?(node.name) && node["role"] != "main"
    end

    def note_beside?(node, note)
      beside = %i[previous_sibling next_sibling].all? do |direction|
        sibling = node.public_send(direction)
        sibling = sibling.public_send(direction) while sibling && note?(sibling, note)
        sibling.nil?
      end
      beside && (note[:long].zero? || note[:headings].positive?)
    end

    def note?(node, note, headed = false)
      return note_text?(Dom.squish(node.content), note, headed) if node.text?
      return true unless node.element?
      return false if BEYOND_TITLE.include?(node.name) || (node.name == "a" && node["href"])
      return false if (note[:elements] += 1) > TITLE_ELEMENTS
      return false if Dom.heading?(node) && (note[:headings] += 1) > 1

      headed ||= title?(node)
      node.children.all? { |child| note?(child, note, headed) }
    end

    def title?(node)
      Dom.heading?(node) || node["role"] == "heading" || Dom.signature(node).match?(TITLE_NAME)
    end

    def note_text?(text, note, headed)
      return true if text.empty?

      chars = Dom.char_count(text)
      note[:chars] += chars
      note[:pieces] += 1
      note[:long] += 1 unless headed || chars <= TITLE_LINE
      note[:chars] <= TITLE && note[:pieces] <= TITLE_PIECES && !text.match?(CONTACT_DETAIL)
    end
  end
end

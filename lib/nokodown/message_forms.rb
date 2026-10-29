# frozen_string_literal: true

module Nokodown
  # Comment, review and contact forms, with the title and notes above them
  # ("Leave a Reply", "Be the first to review", "留言框") in any language.
  # Preprocessor marks them while their controls still say what they ask;
  # they go once the content is chosen, so they never sway that choice.
  module MessageForms
    MARK = "data-nokodown-message-form"
    # An e-mail address, or a phone number of seven digits or more.
    CONTACT_DETAIL = /[^\s@]@[^\s@]|\d(?:[\s().\/-]{0,2}\d){6}/.freeze
    TITLE = 120
    TITLE_PIECES = 3
    TITLE_ELEMENTS = 30
    # Outside a heading, a line as short as "Leave a Reply" or "留言框".
    TITLE_LINE = 40
    BEYOND_TITLE = Set.new(%w[img picture video iframe table ul ol dl h1]).freeze

    module_function

    # Each marked form in the content with the wrappers that add only a short
    # title or note to it.
    def blocks(roots)
      tops = roots.map { |root| Dom.key(root) }.to_set
      roots.flat_map { |root| root.css("form[#{MARK}]").to_a }.map { |form| titled(form, tops) }
    end

    # A heading and a few short lines, without links, pictures, tables,
    # lists, an address or a phone number. The details beside a contact form,
    # the other tabs beside a review form, or the post a reply form follows,
    # are more. Only what the climb adds is read, so a thread of reply forms
    # is read once.
    def titled(form, tops)
      note = { chars: 0, pieces: 0, headings: 0, elements: 0 }
      node = form
      node = node.parent while wrapper?(node.parent, tops) && note_beside?(node, note)
      node
    end

    def wrapper?(node, tops)
      node&.element? && !tops.include?(Dom.key(node)) && node.name != "body" &&
        !Boilerplate::CONTENT_ANCESTORS.include?(node.name) && node["role"] != "main"
    end

    def note_beside?(node, note)
      %i[previous_sibling next_sibling].all? do |direction|
        sibling = node.public_send(direction)
        sibling = sibling.public_send(direction) while sibling && note?(sibling, note)
        sibling.nil?
      end
    end

    def note?(node, note, headed = false)
      return note_text?(Dom.squish(node.content), note, headed) if node.text?
      return true unless node.element?
      return false if BEYOND_TITLE.include?(node.name) || (node.name == "a" && node["href"])
      return false if (note[:elements] += 1) > TITLE_ELEMENTS
      return false if Dom.heading?(node) && (note[:headings] += 1) > 1

      node.children.all? { |child| note?(child, note, headed || Dom.heading?(node)) }
    end

    def note_text?(text, note, headed)
      return true if text.empty?

      chars = Dom.char_count(text)
      note[:chars] += chars
      note[:pieces] += 1
      return false if note[:chars] > TITLE || note[:pieces] > TITLE_PIECES || text.match?(CONTACT_DETAIL)

      headed || chars <= TITLE_LINE
    end
  end
end

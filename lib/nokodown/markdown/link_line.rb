# frozen_string_literal: true

require "strscan"

module Nokodown
  module Markdown
    # A line of Markdown cut into text and links in turn, so that a link can
    # give way to its text, or to nothing, without touching the words around
    # it.
    module LinkLine
      LINK = /\[(#{Text::LINK_TEXT})\]\((#{Text::DESTINATION})\)/.freeze
      # Escapes, image openers and code spans are text, so neither an escaped
      # bracket, an image nor a link written in code is read as a link.
      PLAIN = /\\.|!\[|[^\\!\[`]+/.freeze
      CODE_SPAN = /(`+)(?>[^`]+|(?!\1(?!`))`+)*+\1(?!`)/.freeze
      WORD_START = /\A[*_~`]*[\p{L}\p{N}]/.freeze
      WORD_END = /[\p{L}\p{N}][*_~`]*\z/.freeze

      module_function

      # The pieces, text and links in turn, and each link's segment (its
      # index among the pieces), text and destination. Offsets into a long
      # line of non-ASCII text cost as much as the line, so the line is cut
      # up once.
      def split(line)
        scanner = StringScanner.new(line)
        parts = [+""]
        found = []
        until scanner.eos?
          if scanner.scan(LINK)
            found << [parts.size, scanner[1], scanner[2]]
            parts << scanner.matched << +""
          else
            parts[-1] << (scanner.scan(PLAIN) || scanner.scan(CODE_SPAN) || scanner.getch)
          end
        end
        [parts, found]
      end

      # replacements: segment => the text that takes the link's place, ""
      # to drop it with the spaces before it.
      def join(parts, replacements)
        replacements.each { |segment, text| parts[segment - 1] = parts[segment - 1].sub(/ +\z/, "") if text.empty? }
        parts.each_with_index.map do |part, segment|
          text = replacements[segment]
          text ? spaced(text, parts, replacements, segment) : part
        end.join
      end

      # Links set side by side were told apart by their brackets; a text
      # that would run into the words of the link beside it needs a space.
      # A text after it puts in its own.
      def spaced(text, parts, replacements, segment)
        return text if text.empty?

        before = parts[segment - 1]
        after = parts[segment + 1]
        left = replacements.fetch(segment - 2) { link_text(parts, segment - 2) }
        right = replacements.key?(segment + 2) ? "" : link_text(parts, segment + 2)
        "#{' ' if before.empty? ? beside?(left, text) : before.match?(/[)\]]\z/)}#{text}" \
          "#{' ' if after.empty? ? beside?(text, right) : after.match?(/\A[\[!]/)}"
      end

      def beside?(left, right)
        left.match?(WORD_END) && right.match?(WORD_START)
      end

      def link_text(parts, segment)
        segment.between?(1, parts.size - 1) ? parts[segment][LINK, 1] : ""
      end
    end
  end
end

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
      # An image is text as a whole, so a link written in its alt is not read.
      IMAGE = /!\[#{Text::LINK_TEXT}\]\(#{Text::DESTINATION}\)/.freeze
      WORD_START = /\A[*_~`]*[\p{L}\p{N}]/.freeze
      WORD_END = /[\p{L}\p{N}][*_~`]*\z/.freeze
      # Between two texts that took the places of links a space apart: their
      # brackets told the items apart, and Separators dropped what stood
      # between them.
      ITEMS = " · "
      # Only list and quote markers before a text: it opens its line.
      OPENING = /\A *(?:(?:[-*+]|\d+[.)]|>) +)*\z/.freeze

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
            parts[-1] << (scanner.scan(IMAGE) || scanner.scan(PLAIN) || scanner.scan(CODE_SPAN) || scanner.getch)
          end
        end
        [parts, found]
      end

      # replacements: segment => the text that takes the link's place, ""
      # to drop it with the spaces before it. items: false when Separators
      # kept what stood between the links.
      def join(parts, replacements, items: true)
        replacements.each do |segment, text|
          if text.empty?
            parts[segment - 1] = parts[segment - 1].sub(/ +\z/, "")
          elsif items && !replacements[segment - 2].to_s.empty? && parts[segment - 1].match?(/\A +\z/)
            parts[segment - 1] = ITEMS
          elsif parts[segment - 1].end_with?("\\!") && !text.start_with?("[")
            # Inline escaped the "!" only for the link's bracket.
            parts[segment - 1] = "#{parts[segment - 1].delete_suffix('\\!')}!"
          end
        end
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
        text = escaped(text, before, after.empty? ? replacements[segment + 2].to_s : after, segment)
        "#{' ' if before.empty? ? beside?(left, text) : before.match?(/[)\]]\z/)}#{text}#{' ' if space_after?(text, after, right)}"
      end

      # Brackets Text.link_text escaped for the link read as written once it
      # is gone, unless they would make a link. A closing bracket before "("
      # would make a link of the two. A text that opens its line is escaped
      # as a paragraph's own text is: block markers, and an asterisk that
      # would open a list item.
      def escaped(text, before, following, segment)
        bare = text.gsub(/\\([\[\]])/, '\1')
        text = bare unless bare.match?(/\][(\[]/)
        text = text.sub(/(?<!\\)((?:\\\\)*)\]\z/) { "#{Regexp.last_match(1)}\\]" } if following.start_with?("(")
        return text unless segment == 1 && before.match?(OPENING)

        Text.escape_line_starts(text.sub(/\A\*+(?=\s|\z)/) { |run| "\\*" * run.length })
      end

      # A "!" before a link would make an image of it.
      def space_after?(text, after, right)
        return after.match?(/\A!?\[/) unless after.empty?

        beside?(text, right) || (text.end_with?("!") && !right.empty?)
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

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
      # between them. Single words a space apart ("2 3 4", "Home About")
      # read as items without it.
      ITEMS = " · "
      # What stands between two links of one run.
      RUN_GAP = /\A *\z/.freeze
      # A sentence runs on in lowercase words; a label ("Tags:"), a date or
      # a menu's capitalised or CJK items do not.
      WORD_BEFORE = /\p{Ll}[*_~`]* +\z/.freeze
      WORD_AFTER = /\A +[*_~`]*[\p{Ll}(]/.freeze
      # Only list and quote markers before a text: it opens its line.
      OPENING = /\A *(?:(?:[-*+]|\d+[.)]|>) +)*\z/.freeze
      MARKERS = /\A *(?:(?:[-*+]|\d+[.)]|>)(?: +|\z))*/.freeze

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
      # to drop it with the spaces before it.
      def join(parts, replacements)
        items = replacements.size > 1 ? item_segments(parts, replacements) : Set.new
        replacements.each do |segment, text|
          if text.empty?
            parts[segment - 1] = parts[segment - 1].sub(/ +\z/, "")
          elsif items.include?(segment) && !replacements[segment - 2].to_s.empty? && parts[segment - 1].match?(/\A +\z/)
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
        own = address(parts, segment)
        left = "" if own == address(parts, segment - 2) && inside_word?(left, text)
        right = "" if own == address(parts, segment + 2) && inside_word?(text, right)
        "#{' ' if space_before?(text, before, left)}#{text}#{' ' if space_after?(text, after, right)}"
      end

      # The segments of the runs of links set a space apart that take ITEMS:
      # a run with a text of more than a word, and not a phrase linked in
      # pieces, with words running on at both ends ("Read the [New York](…)
      # [Times](…) today").
      def item_segments(parts, replacements)
        runs = (1...parts.size).step(2).slice_when { |_, link| !parts[link - 1].match?(RUN_GAP) }
        runs.each_with_object(Set.new) do |run, items|
          next if run.size < 2 || (parts[run.first - 1].match?(WORD_BEFORE) && parts[run.last + 1].match?(WORD_AFTER))
          next unless run.any? { |link| replacements.fetch(link) { link_text(parts, link) }.include?(" ") }

          items.merge(run)
        end
      end

      # A word after an image or a parenthesis ("(09/08)") needs a space,
      # punctuation does not ("(1983),"). A closing bracket before "(" would
      # make a link of the two.
      def space_before?(text, before, left)
        return beside?(left, text) if before.empty?

        before.end_with?("]") || (before.end_with?(")") && text.match?(WORD_START))
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
        return after.start_with?("![") unless after.empty?

        beside?(text, right) || (text.end_with?("!") && !right.empty?)
      end

      def beside?(left, right)
        left.match?(WORD_END) && right.match?(WORD_START)
      end

      # Two links to one address that meet inside a word are one link the
      # page split with markup, as a drop cap ("L" "ien"): no brackets told
      # them apart.
      def inside_word?(left, right)
        left.match?(/\p{L}\z/) && right.match?(/\A\p{Ll}/)
      end

      # A line its links left with nothing but symbols ("-", "=", "»") says
      # nothing, as Separators finds of such a line without links, and a "-"
      # or "=" under a line of text would make a heading of it. A table row
      # keeps its cells.
      def bare?(line)
        return false if line.start_with?("|")

        text = line.sub(MARKERS, "")
        text.match?(Separators::SYMBOL_LINE) && !text.match?(Separators::EMOTICON)
      end

      def address(parts, segment)
        parts[segment][LINK, 2] if segment.between?(1, parts.size - 1)
      end

      def link_text(parts, segment)
        segment.between?(1, parts.size - 1) ? parts[segment][LINK, 1] : ""
      end
    end
  end
end

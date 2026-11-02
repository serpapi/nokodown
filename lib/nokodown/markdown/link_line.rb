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
      # A letter of a script written with spaces between words, or a digit.
      SPACED_END = /(?:#{Inline::SPACED.source}|\p{Nd})[*_~`]*\z/.freeze
      SPACED_START = /\A[*_~`]*(?:#{Inline::SPACED.source}|\p{Nd})/.freeze
      # Between two texts that took the places of links a space apart: their
      # brackets told the items apart, and Separators dropped what stood
      # between them. Single words a space apart ("2 3 Next >>", "Home
      # About") read as items without it.
      ITEMS = " · "
      # What stands between two links of one run: spaces, or the item a menu
      # writes without a link, its current page ("[Home](…) Blog [Case
      # Law](…)"): a few words, each opening in a capital or a digit, with no
      # punctuation of a sentence. A sentence has lowercase words ("1 hour
      # ago by"); in a script without case the two look alike.
      RUN_GAP = /\A *\z/.freeze
      PLAIN_ITEM = /\A +[^.,;:!?()\[\]|<>«»‹›·•]*[\p{L}\p{N}][*_]* +\z/.freeze
      PLAIN_ITEM_WORD = /\A[*_]*[\p{Lu}\p{Lt}\p{N}]/.freeze
      PLAIN_ITEM_WORDS = 4
      # A sentence runs on in lowercase words; a label ("Tags:"), a date or
      # a menu's capitalised or CJK items do not. It can end on a phrase
      # linked in pieces ("by [Oxford University](…) [Press](…).").
      WORD_BEFORE = /\p{Ll}[*_~`]* +\z/.freeze
      WORD_AFTER = /\A +[*_~`]*[\p{Ll}(]/.freeze
      SENTENCE_END = /\A[*_~`]*[.,;:!?](?!\S)/.freeze
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
        items = item_segments(parts, replacements)
        set_apart_plain_items(parts, replacements, items)
        replacements.each do |segment, text|
          if text.empty?
            parts[segment - 1] = parts[segment - 1].sub(/ +\z/, "")
          elsif items.include?(segment) && !replacements[segment - 2].to_s.empty? && parts[segment - 1].match?(/\A +\z/)
            parts[segment - 1] = ITEMS
          elsif parts[segment - 1].end_with?("\\!") && !text.start_with?("[")
            # Inline escaped the "!" only for the link's bracket.
            parts[segment - 1] = "#{parts[segment - 1].delete_suffix('\\!')}!"
          elsif Text.doubled_end?(parts[segment - 1], text)
            # Inline left it doubled only for the link's bracket.
            parts[segment - 1] = parts[segment - 1].chop
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

      # The segments of the runs of links that take ITEMS: a run with a link
      # text of more than a word, and not a phrase linked in pieces. A plain
      # item does not count: "9 **10**" in a pager is two.
      def item_segments(parts, replacements)
        runs = (1...parts.size).step(2).slice_when { |_, link| !run_gap?(parts[link - 1]) }
        runs.each_with_object(Set.new) do |run, items|
          next if run.size < 2 || phrase?(parts[run.first - 1], parts[run.last + 1])
          next unless run.any? { |link| words?(replacements.fetch(link) { link_text(parts, link) }) }

          items.merge(run)
        end
      end

      def run_gap?(gap)
        gap.match?(RUN_GAP) || plain_item?(gap)
      end

      def plain_item?(gap)
        return false unless gap.match?(PLAIN_ITEM)

        words = gap.split
        words.size <= PLAIN_ITEM_WORDS && words.all? { |word| word.match?(PLAIN_ITEM_WORD) }
      end

      # A phrase linked in pieces runs on into its sentence at both ends
      # ("Read the [New York](…) [Times](…) today"), or opens or ends it; a
      # menu or a list of tags does neither.
      def phrase?(before, after)
        if before.match?(WORD_BEFORE)
          after.match?(WORD_AFTER) || after.match?(SENTENCE_END)
        else
          before.match?(OPENING) && after.match?(WORD_AFTER)
        end
      end

      # More than one piece in letters or digits: a sign beside a word
      # ("Next >>", "[ date ]") leaves it a word.
      def words?(text)
        text.split.count { |piece| piece.match?(/[\p{L}\p{N}]/) } > 1
      end

      # A plain item had only the brackets of the links beside it to end it:
      # it takes ITEMS on each side where a link gave way to its text.
      def set_apart_plain_items(parts, replacements, items)
        gaps = (2...parts.size - 1).step(2).select { |gap| items.include?(gap - 1) && items.include?(gap + 1) && plain_item?(parts[gap]) }
        gaps.each do |gap|
          parts[gap] = parts[gap].sub(/\A +/, ITEMS) unless replacements[gap - 1].to_s.empty?
          parts[gap] = parts[gap].sub(/ +\z/, ITEMS) unless replacements[gap + 1].to_s.empty?
        end
      end

      # A word after an image or a parenthesis ("(09/08)") needs a space,
      # punctuation does not ("(1983),"). A closing bracket before "(" would
      # make a link of the two.
      def space_before?(text, before, left)
        return beside?(left, text) if before.empty?

        (before.end_with?("]") && text.start_with?("(")) || (before.end_with?(")") && text.match?(WORD_START))
      end

      # Brackets Text.link_text escaped for the link read as written once it
      # is gone, unless they would make a link. A closing bracket before "("
      # would make a link of the two. A text that opens its line is escaped
      # as a paragraph's own text is: block markers, and an asterisk that
      # would open a list item. A bracket after an escaped backslash ("\\[")
      # was not escaped.
      def escaped(text, before, following, segment)
        bare = text.gsub(/(?<!\\)((?:\\\\)*)\\([\[\]])/, '\1\2')
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

      # Only its brackets told a link apart from the words set against it
      # ("[PaulP](…)January", "[0](…)6 mins"): its text alone would run into
      # them where words are written with spaces. A word the page split with
      # markup ("L" "ien") reads whole without them.
      def glued?(parts, segment)
        text = parts[segment][LINK, 1]
        fused?(parts[segment - 1], text) || fused?(text, parts[segment + 1])
      end

      def fused?(left, right)
        left.match?(SPACED_END) && right.match?(SPACED_START) && !inside_word?(left, right)
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
      # keeps its cells. Only the markers the line had before its links
      # changed are passed over: a text in a link's place ("2020.") is what
      # the item says.
      def bare?(line, original)
        return false if line.start_with?("|")

        text = line[original[MARKERS].rstrip.length..].to_s.lstrip
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

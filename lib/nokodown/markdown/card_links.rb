# frozen_string_literal: true

require "strscan"

module Nokodown
  module Markdown
    # A card links its page from its title and again from a date, a price, a
    # button or the ellipsis of its excerpt. The title keeps the link. A
    # button ("Read more", "Voir") alone on its line or after the excerpt
    # only repeats it and goes, as does a second copy of the title; other
    # repeats keep their text. A button counts as one only when the page
    # uses it for several pages; ReadMoreLinks already took the read-more
    # labels it can tell from the DOM.
    class CardLinks
      LINK = /\[(#{Text::LINK_TEXT})\]\((#{Text::DESTINATION})\)/.freeze
      # Escapes, image openers and code spans are text, so neither an escaped
      # bracket, an image nor a link written in code is read as a link.
      PLAIN = /\\.|!\[|[^\\!\[`]+/.freeze
      CODE_SPAN = /(`+)(?>[^`]+|(?!\1(?!`))`+)*+\1(?!`)/.freeze
      ITEM = /\A(?:[-*+]|\d+\.) /.freeze
      MARKERS = /\A\s*(?:(?:[-*+]|\d+\.)(?:\s+|\z))*\z/.freeze
      # A button follows the end of a sentence or of another link.
      AFTER_SENTENCE = /[.…!?。！？:)\]*]\s*\z/.freeze
      CARD_UNITS = 4
      SEPARATE = %i[list table].freeze
      INITIALS = /\A\p{Lu}{1,4}\z/.freeze
      WORD_START = /\A[*_~`]*[\p{L}\p{N}]/.freeze
      WORD_END = /[\p{L}\p{N}][*_~`]*\z/.freeze

      # segment: the link's index among the pieces of its line, which
      # alternate text and links.
      Link = Struct.new(:unit, :card, :block, :line, :segment, :text, :destination, :heading) do
        def page
          RedundantImages.page(destination)
        end

        def fragment
          destination[/#.*/m]
        end

        def label
          @label ||= Text.plain(text).downcase
        end
      end

      def initialize(blocks)
        @blocks = blocks
      end

      def call
        @lines = {}
        @segments = {}
        @edits = Hash.new { |edits, block| edits[block] = Hash.new { |lines, line| lines[line] = {} } }
        pages = links.group_by(&:page)
        @generic = generic_texts(pages)
        cards = pages.each_value.flat_map { |occurrences| cards(occurrences) }.select { |card| card.size > 1 }
        keepers = cards.map { |card| keeper(card) }
        @buttons = buttons(cards.zip(keepers))
        cards.zip(keepers).each { |card, keeper| plan(card, keeper) }
        return @blocks if @edits.empty?

        @blocks.each_with_index.filter_map do |block, index|
          next block unless @edits.key?(index)

          block.text = edited(index)
          block if block.text.match?(/[\p{L}\p{N}]/)
        end
      end

      private

      # A heading opens a card that runs to the next heading; a list's
      # top-level items and a table's rows are cards of their own.
      def links
        unit = card = -1
        previous = nil
        @blocks.each_with_index.flat_map do |block, index|
          card += 1 if block.kind == :heading || SEPARATE.include?(block.kind) || SEPARATE.include?(previous)
          previous = block.kind
          next [] if block.kind == :code

          unit += 1
          lines = @lines[index] = block.text.split("\n", -1)
          code = CodeBlock.nested_code_lines(lines)
          lines.each_with_index.flat_map do |line, number|
            if number.positive? && piece?(block.kind, line)
              unit += 1
              card += 1
            end
            next [] if code[number] || !line.include?("](")

            line_links(line, [unit, card, index, number], block.kind == :heading)
          end
        end
      end

      def piece?(kind, line)
        kind == :table || (kind == :list && line.match?(ITEM))
      end

      def line_links(line, place, heading)
        parts, found = segments(line)
        @segments[place.last(2)] = parts unless found.empty?
        found.map { |segment, text, destination| Link.new(*place, segment, text, destination, heading) }
      end

      # The line split into text and links in turn, and each link's segment,
      # text and destination. Offsets into a long line of non-ASCII text
      # cost as much as the line, so the line is cut up once.
      def segments(line)
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

      # Occurrences close together in one card.
      def cards(occurrences)
        occurrences.slice_when { |a, b| a.card != b.card || b.unit - a.unit >= CARD_UNITS }.to_a
      end

      # Link texts used for several pages, about once each: "Read more",
      # "Voir", "View details". A text used again and again for a few pages,
      # as a store's location in each of its products, belongs to them.
      def generic_texts(pages)
        uses = pages.each_value.flat_map { |occurrences| occurrences.map(&:label) }.tally
        pages = pages.each_value.flat_map { |occurrences| occurrences.map(&:label).uniq }.tally
        pages.select { |text, count| count > 1 && count * 2 >= uses[text] }.keys.to_set
      end

      # The title is the heading, or the first link in words of its own; a
      # date, a price, a count or initials ("TFH") before it are not one.
      # Without one, the longest text in words keeps the link.
      def keeper(card)
        card.find(&:heading) || card.find { |link| title?(link) } ||
          card.select { |link| link.label.match?(/\p{L}/) }.max_by { |link| link.label.length } || card.first
      end

      # A button reads the same in every card, beside whatever else the card
      # repeats. Texts that never share a card but take turns among the same
      # cards are values of one field, as a car's "Sold" among "Available",
      # or a match's "Live" and "Starting soon" each over a run of cards;
      # a section of their own, or links after the cards, are not.
      def buttons(cards)
        @shared = Hash.new { |all, text| all[text] = Set.new }
        places = Hash.new { |all, text| all[text] = [] }
        cards.each do |card, keeper|
          texts = card.reject { |link| link.equal?(keeper) }.map(&:label).select { |text| words?(text) }.uniq
          texts.each do |text|
            @shared[text].merge(texts)
            places[text] << card.first.card
          end
        end
        @spans = places.transform_values(&:minmax)
        @runs = places.transform_values { |numbers| numbers.uniq.size }
        texts = @spans.keys
        texts.select { |text| @generic.include?(text) }.reject { |text| texts.any? { |other| values?(text, other) } }.to_set
      end

      def values?(text, other)
        return false if @shared[text].include?(other)

        first, last = @spans[text]
        other_first, other_last = @spans[other]
        return true if first <= other_last && other_first <= last

        (last + 1 == other_first || other_last + 1 == first) && @runs[text] > 1 && @runs[other] > 1
      end

      def words?(text)
        !text.match?(/\d/) && text.match?(/\p{L}/)
      end

      # Links to other sections of the title's page (#2 after #1) are not
      # repeats.
      def plan(card, keeper)
        card.each do |link|
          next if link.equal?(keeper) || (link.fragment && keeper.fragment && link.fragment != keeper.fragment)

          @edits[link.block][link.line][link.segment] = button?(link, keeper) ? "" : link.text
        end
      end

      def title?(link)
        text = link.label
        return false if text.match?(/\d/) || @generic.include?(text) || Text.plain(link.text).match?(INITIALS)

        text.match?(/\p{L}/)
      end

      # Dates and counts say something even when every card has the same one.
      def button?(link, keeper)
        text = link.label
        return false if text.match?(/\d/) || !text.match?(/\p{L}/)
        return false unless @buttons.include?(text) || text == keeper.label

        standalone?(link)
      end

      # The link ends its line, alone or after a sentence, and does not open
      # an item whose other lines would lose their marker.
      def standalone?(link)
        parts = @segments[[link.block, link.line]]
        return false unless link.segment == parts.size - 2 && parts.last.strip.empty?

        before = parts.first(link.segment).join
        return before.match?(AFTER_SENTENCE) unless before.match?(MARKERS)

        before.strip.empty? || !@lines[link.block][link.line + 1].to_s.match?(/\A +\S/)
      end

      # Lines the edits leave with only list markers go.
      def edited(index)
        lines = @lines[index]
        edits = @edits[index]
        lines.each_with_index.filter_map do |line, number|
          next line unless edits.key?(number)

          result = edited_line(@segments[[index, number]], edits[number])
          result unless result.match?(MARKERS) && !line.match?(MARKERS)
        end.join("\n")
      end

      def edited_line(parts, replacements)
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

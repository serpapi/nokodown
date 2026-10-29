# frozen_string_literal: true

module Nokodown
  module Markdown
    # A card links its page from its title and again from a date, a price, a
    # button or the ellipsis of its excerpt. The title keeps the link. A
    # button ("Read more", "Voir") alone on its line or after the excerpt
    # only repeats it and goes; other repeats keep their text without the URL.
    class RepeatedLinks
      LINK = /(?<!!)\[((?:\\.|[^\\\[\]\n]|\[(?:\\.|[^\\\[\]\n])*\])*)\]\(((?:[^()\s]|\([^()\s]*\))*)\)/.freeze
      ITEM = /^(?:[-*+]|\d+\.) /.freeze
      MARKERS = /\A\s*(?:(?:[-*+]|\d+\.)\s+)*\z/.freeze
      # A button follows the end of a sentence or of another link.
      AFTER_SENTENCE = /[.…!?。！？:)\]*]\s*\z/.freeze
      CARD_UNITS = 4
      SEPARATE = %i[list table].freeze
      BUTTON_WORDS = 3
      # Characters, a wide one (Chinese, Japanese, Korean) counting twice.
      BUTTON_WIDTH = 20
      WIDE = /[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}]/.freeze

      Link = Struct.new(:unit, :card, :block, :range, :text, :destination, :heading) do
        def page
          RedundantImages.page(destination)
        end

        def fragment
          destination[/#.*/m]
        end
      end

      def initialize(blocks)
        @blocks = blocks
      end

      def call
        @edits = Hash.new { |edits, block| edits[block] = [] }
        pages = links.group_by(&:page)
        @generic = generic_texts(pages)
        pages.each_value { |occurrences| cards(occurrences).each { |card| plan(card) } }
        return @blocks if @edits.empty?

        @blocks.each_with_index.filter_map do |block, index|
          next block unless @edits.key?(index)

          block.text = edited(block.text, @edits[index])
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

          pieces(block).each_with_index.flat_map do |range, piece|
            card += 1 if piece.positive?
            block_links(block, index, range, unit += 1, card)
          end
        end
      end

      def pieces(block)
        text = block.text
        starts = case block.kind
                 when :list then text.enum_for(:scan, ITEM).map { Regexp.last_match.begin(0) }
                 when :table then text.enum_for(:scan, /^/).map { Regexp.last_match.begin(0) }
                 else [0]
                 end
        starts = [0] | starts
        starts.each_with_index.map { |start, index| start...(starts[index + 1] || text.length) }
      end

      def block_links(block, index, range, unit, card)
        block.text[range].enum_for(:scan, LINK).map do
          match = Regexp.last_match
          offset = range.first + match.begin(0)
          Link.new(unit, card, index, offset...(range.first + match.end(0)), match[1], match[2], block.kind == :heading)
        end
      end

      # Occurrences close together in one card.
      def cards(occurrences)
        occurrences.slice_when { |a, b| a.card != b.card || b.unit - a.unit >= CARD_UNITS }
      end

      # Link texts used for several pages: "Read more", "Voir", "View details".
      def generic_texts(pages)
        texts = pages.flat_map { |_, occurrences| occurrences.map { |link| label(link) }.uniq }
        texts.tally.select { |_, count| count > 1 }.keys.to_set
      end

      # The title is the heading, or the first link in words of its own; a
      # date, a price or a count before it is not one. Links to other
      # sections of the title's page (#2 after #1) are not repeats.
      def plan(card)
        return if card.size < 2

        keeper = card.find(&:heading) || card.find { |link| title?(link) } || card.first
        (card - [keeper]).each do |link|
          next if link.fragment && keeper.fragment && link.fragment != keeper.fragment

          @edits[link.block] << [link.range, button?(link, keeper) ? "" : link.text]
        end
      end

      def title?(link)
        text = label(link)
        text.match?(/\p{L}/) && !text.match?(/\d/) && !@generic.include?(text)
      end

      def button?(link, keeper)
        text = label(link)
        return false unless text.match?(/\p{L}/) && !text.match?(/\d/)
        return false unless @generic.include?(text) || short?(text) || text == label(keeper)

        standalone?(@blocks[link.block].text, link.range)
      end

      def short?(text)
        text.split.size <= BUTTON_WORDS && text.length + text.scan(WIDE).size <= BUTTON_WIDTH
      end

      def label(link)
        Text.plain(link.text).downcase
      end

      # The link ends its line, alone or after a sentence, and does not open
      # an item whose other lines would lose their marker.
      def standalone?(text, range)
        line_start = range.first.zero? ? 0 : text.rindex("\n", range.first - 1)&.succ.to_i
        line_stop = text.index("\n", range.last) || text.length
        return false unless text[range.last...line_stop].strip.empty?

        before = text[line_start...range.first]
        return before.match?(AFTER_SENTENCE) unless before.match?(MARKERS)

        before.strip.empty? || !text[line_stop..].to_s.match?(/\A\n +\S/)
      end

      # Links set side by side were told apart by their brackets; their text
      # needs a space instead.
      def spaced(text, before, after)
        return text if text.empty?

        "#{' ' if before.match?(/[)\]]/)}#{text}#{' ' if after.match?(/[\[!]/)}"
      end

      # Lines the edits leave with only list markers go; links never span
      # lines, so the lines before and after the edits pair up.
      def edited(text, edits)
        result = edits.sort_by { |range, _| -range.first }.reduce(text.dup) do |out, (range, replacement)|
          start = range.first
          start -= 1 while replacement.empty? && start.positive? && out[start - 1] == " "
          out[start...range.last] = spaced(replacement, start.positive? ? out[start - 1] : "", out[range.last].to_s)
          out
        end
        before = text.split("\n", -1)
        lines = result.split("\n", -1)
        lines.reject.with_index { |line, index| line.match?(MARKERS) && !before[index].match?(MARKERS) }.join("\n")
      end
    end
  end
end

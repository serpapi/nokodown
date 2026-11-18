# frozen_string_literal: true

module Nokodown
  module Markdown
    # Numbers without the label that says what they count, and labels
    # without the value they introduce.
    module Orphans
      NUMBERS = /\A\d{1,3}(?:\s+\d{1,3})?\z/.freeze
      # A number, with its separators and unit: "4.155", "393m²", "€24".
      VALUE = /\A\p{Sc}?\d[\d.,\s]*[\p{L}\p{Sc}%²³]{0,4}\z/.freeze
      DATE = %r{\A\d{1,4}[./-]\d{1,2}[./-]\d{1,4}\z}.freeze
      SEQUENCE = /\A[01](?:\s+\d{1,2})+\z/.freeze
      TIME = /(?:\d{1,2}:)?\d{1,2}:\d{2}/.freeze
      # A player shows the elapsed time and the duration, run together
      # ("0:000:00") or apart ("0:00 / 3:45"); a lone "00:00" is a slot in a
      # schedule.
      PLAYER_TIME = %r{\A\s*#{TIME}(?:\s*(?:/\s*)?#{TIME})+\s*\z}.freeze
      PLAYER_START = /(?<![\d:])0?0:00/.freeze
      PLAYER_LENGTH = 30
      LABEL_LENGTH = 40
      LABEL_END = /[\p{L}:：?)]\z/.freeze
      EMPTY_LABEL_LENGTH = 30
      COLON_END = /[:：]\z/.freeze
      LINK_ONLY = /\A\**\[[^\]]*\]\([^)]*\)\**\z/.freeze

      module_function

      def call(blocks)
        empty = empty_labels(blocks)
        columns = columns(blocks)
        blocks.reject.with_index do |block, index|
          next true if empty.include?(index)
          next false unless block.kind == :paragraph && !block.text.include?("](") && !columns.include?(index)

          counter?(blocks, index, Text.plain(block.text))
        end
      end

      # Comment and like counts, the badges numbering FAQ entries or steps,
      # slide numbers and a media player's "0:00" readout. Three or more
      # numbers in a row are a phone number unless they count up from one.
      def counter?(blocks, index, text)
        player_time?(text) || slide_numbers?(text) || (text.match?(NUMBERS) && !labelled?(blocks, index))
      end

      # The fields of a form whose inputs are gone ("Name:", "E-mail:"), or a
      # "Tags:" whose tags are, end the page or a section, and the heading of
      # a section they were all of goes with them. A lone label over a
      # heading may name it, and labels followed by text may be a template a
      # post sets out for readers to fill in.
      def empty_labels(blocks)
        labels = blocks.map { |block| colon_label_block?(block) }
        runs = blocks.each_index.chunk_while { |a, b| labels[a] && labels[b] }.select { |run| labels[run.first] }
        runs.flat_map do |run|
          following = blocks[run.last + 1]
          next [] unless following.nil? || (following.kind == :heading && run.size > 1)

          heading = run.first.positive? ? blocks[run.first - 1] : nil
          labels_section?(heading, following) ? [run.first - 1, *run] : run
        end.to_set
      end

      # The page's title stays even when its form is all it held, and so
      # does a heading longer than a label, such as a video's description
      # over a "More videos:" whose list is gone: it names no form.
      def labels_section?(heading, following)
        heading&.kind == :heading && heading.level > 1 && (following.nil? || following.level <= heading.level) &&
          Text.plain(Cleanup.heading_text(heading)).length <= LABEL_LENGTH
      end

      # Numbers side by side are the columns of a row, such as a forum's
      # posts and threads or a house's bedrooms and floor area, unless they
      # count up like the options of a picker or the pages of a slider. A
      # count beside a date is a post's views.
      def columns(blocks)
        values = blocks.map { |block| value_block?(block) }
        runs = blocks.each_index.chunk_while { |a, b| values[a] && values[b] }.select { |run| values[run.first] && run.size > 1 }
        runs.reject { |run| counting?(run.map { |index| Text.plain(blocks[index].text) }) }.flatten.to_set
      end

      def value_block?(block)
        return false unless block.kind == :paragraph && !block.text.include?("](")

        text = Text.plain(block.text)
        text.match?(VALUE) && !text.match?(DATE)
      end

      def counting?(texts)
        return false unless texts.all? { |text| text.match?(/\A\d+\z/) }

        numbers = texts.map(&:to_i)
        numbers.each_cons(2).all? { |a, b| b == a + 1 } && (numbers.size > 2 || numbers.first <= 1)
      end

      def colon_label_block?(block)
        block.kind == :paragraph && !block.text.include?("](") && colon_label?(Text.plain(block.text))
      end

      def colon_label?(text)
        text.length <= EMPTY_LABEL_LENGTH && text.match?(COLON_END) && text.match?(/\p{L}/)
      end

      def player_time?(text)
        text.length <= PLAYER_LENGTH && text.match?(PLAYER_START) && text.match?(PLAYER_TIME)
      end

      def slide_numbers?(text)
        return false unless text.match?(SEQUENCE)

        numbers = text.split.map(&:to_i)
        numbers.each_cons(2).all? { |a, b| b == a + 1 }
      end

      # A number right after a heading or a label, or right before a label,
      # is that label's value; a number before a heading is its position.
      # Text that runs on from the number ("17" over "stores in the city")
      # says what it counts.
      def labelled?(blocks, index)
        previous = index.positive? ? blocks[index - 1] : nil
        following = blocks[index + 1]
        previous&.kind == :heading || label?(previous) || label?(following) || continues?(following)
      end

      def continues?(block)
        block&.kind == :paragraph && Text.plain(block.text).match?(/\A[\p{Ll}\p{Lo}]/)
      end

      # A short line of words that is not a link of its own, such as
      # "Bedrooms" or "Views:".
      def label?(block)
        return false unless block&.kind == :paragraph && !block.text.include?("![") && !block.text.match?(LINK_ONLY)

        text = Text.plain(block.text)
        text.length <= LABEL_LENGTH && text.match?(LABEL_END)
      end
    end
  end
end

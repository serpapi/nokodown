# frozen_string_literal: true

module Nokodown
  module Markdown
    # Numbers that say nothing without a label: comment and like counts,
    # the badges numbering FAQ entries or steps, slide numbers, and a media
    # player's "0:00" readout. A number right after a heading or a label,
    # or right before a label, is that label's value and stays. Three or
    # more numbers in a row are a phone number unless they count up from
    # one, like slide numbers.
    module Counters
      NUMBERS = /\A\d{1,3}(?:\s+\d{1,3})?\z/.freeze
      SEQUENCE = /\A[01](?:\s+\d{1,2})+\z/.freeze
      PLAYER_TIME = %r{\A(?:\s*/?\s*(?:\d{1,2}:)?\d{1,2}:\d{2})+\z}.freeze
      PLAYER_START = /(?<![\d:])0?0:00/.freeze
      LABEL_LENGTH = 40
      LABEL_END = /[\p{L}:：?)]\z/.freeze
      LINK_ONLY = /\A\**\[[^\]]*\]\([^)]*\)\**\z/.freeze

      module_function

      def call(blocks)
        blocks.reject.with_index do |block, index|
          next false unless block.kind == :paragraph && !block.text.include?("](")

          text = Text.plain(block.text)
          player_time?(text) || slide_numbers?(text) || (text.match?(NUMBERS) && !labelled?(blocks, index))
        end
      end

      def player_time?(text)
        text.match?(PLAYER_TIME) && text.match?(PLAYER_START)
      end

      def slide_numbers?(text)
        return false unless text.match?(SEQUENCE)

        numbers = text.split.map(&:to_i)
        numbers.each_cons(2).all? { |a, b| b == a + 1 }
      end

      # What a number before a heading counts is the heading's position.
      def labelled?(blocks, index)
        previous = index.positive? ? blocks[index - 1] : nil
        following = blocks[index + 1]
        previous&.kind == :heading || label?(previous) || label?(following)
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

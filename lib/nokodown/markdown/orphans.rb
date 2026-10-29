# frozen_string_literal: true

module Nokodown
  module Markdown
    # Numbers without the label that says what they count, and labels
    # without the value they introduce.
    module Orphans
      NUMBERS = /\A\d{1,3}(?:\s+\d{1,3})?\z/.freeze
      SEQUENCE = /\A[01](?:\s+\d{1,2})+\z/.freeze
      PLAYER_TIME = %r{\A(?:\s*/?\s*(?:\d{1,2}:)?\d{1,2}:\d{2})+\z}.freeze
      PLAYER_START = /(?<![\d:])0?0:00/.freeze
      LABEL_LENGTH = 40
      LABEL_END = /[\p{L}:：?)]\z/.freeze
      EMPTY_LABEL_LENGTH = 30
      COLON_END = /[:：]\z/.freeze
      LINK_ONLY = /\A\**\[[^\]]*\]\([^)]*\)\**\z/.freeze

      module_function

      def call(blocks)
        blocks.reject.with_index do |block, index|
          next false unless block.kind == :paragraph && !block.text.include?("](")

          text = Text.plain(block.text)
          counter?(blocks, index, text) || empty_label?(blocks, index, text)
        end
      end

      # Comment and like counts, the badges numbering FAQ entries or steps,
      # slide numbers and a media player's "0:00" readout. Three or more
      # numbers in a row are a phone number unless they count up from one.
      def counter?(blocks, index, text)
        player_time?(text) || slide_numbers?(text) || (text.match?(NUMBERS) && !labelled?(blocks, index))
      end

      # The fields of a form whose inputs are gone ("Name:", "E-mail:"), or a
      # "Tags:" whose tags are: nothing follows the label but another label
      # or the end of the page. The last field of a form may be followed by
      # the next section; a lone label over a heading may name it.
      def empty_label?(blocks, index, text)
        return false unless colon_label?(text)

        following = blocks[index + 1]
        return true if following.nil? || colon_label_block?(following)

        following.kind == :heading && index.positive? && colon_label_block?(blocks[index - 1])
      end

      def colon_label_block?(block)
        block.kind == :paragraph && !block.text.include?("](") && colon_label?(Text.plain(block.text))
      end

      def colon_label?(text)
        text.length <= EMPTY_LABEL_LENGTH && text.match?(COLON_END) && text.match?(/\p{L}/)
      end

      def player_time?(text)
        text.match?(PLAYER_TIME) && text.match?(PLAYER_START)
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

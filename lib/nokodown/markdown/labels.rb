# frozen_string_literal: true

module Nokodown
  module Markdown
    # A label and its value, or a number and its unit, that a page sets on
    # lines or in blocks of their own ("Type:" over "Condo", "27" over
    # "Nov") read as one line. A label over three or more short lines
    # introduces a list ("Check all that apply:") and stays on its own.
    module Labels
      LABEL = /\A[^\s#>|`\-\d!][^\n]{0,38}[:：]\**\z/.freeze
      NUMBER = /\A\d[\d.,]{0,7}\z/.freeze
      VALUE = /\A(?!!\[)[^\s#>|`\-](?![^\n]*[:：]\**\z)[^\n]{0,59}\z/.freeze
      UNIT = /\A\p{L}[^\n]{0,29}\z/.freeze

      module_function

      def lines(text)
        lines = text.split("\n")
        joined(lines, joins(lines)) { |first, second| "#{first} #{second}" }.join("\n")
      end

      def blocks(blocks)
        joins = joins(blocks.map { |block| block.text if block.kind == :paragraph })
        joined(blocks, joins) { |first, second| Block.new(:paragraph, "#{first.text} #{second.text}") }
      end

      def joined(items, joins)
        items.each_with_index.each_with_object([]) do |(item, index), kept|
          if joins.include?(index - 1)
            kept[-1] = yield(kept[-1], item)
          else
            kept << item
          end
        end
      end

      # Indexes of the texts that take the next one onto their line.
      def joins(texts)
        texts.each_index.select do |index|
          first, second, *rest = texts[index, 4]
          next false if first.nil? || second.nil?

          (first.match?(NUMBER) && second.match?(UNIT)) || (first.match?(LABEL) && second.match?(VALUE) && !list?(rest))
        end.to_set
      end

      def list?(rest)
        rest.size == 2 && rest.all? { |text| !text.nil? && text.match?(VALUE) && !text.match?(/[:：]/) }
      end
    end
  end
end

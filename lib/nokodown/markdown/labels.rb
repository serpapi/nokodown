# frozen_string_literal: true

module Nokodown
  module Markdown
    # A label and its value, or a number and its unit, that a page sets on
    # lines or in blocks of their own ("Type:" over "Condo", "27" over
    # "Nov") read as one line. A label over three or more short lines
    # introduces a list ("Check all that apply:") and stays on its own. A
    # number after a name ("Stories" over "1.5") is that name's value, and
    # the name after it is the next value's, not its unit.
    module Labels
      LABEL = /\A[^\s#>|`\-\d!][^\n]{0,38}[:：]\**\z/.freeze
      NUMBER = /\A\d[\d.,]{0,7}\z/.freeze
      VALUE = /\A(?!!\[)[^\s#>|`\-](?![^\n]*[:：]\**\z)[^\n]{0,59}\z/.freeze
      UNIT = /\A\p{L}[^\n]{0,29}\z/.freeze
      NAME = /\A(?!.*\]\()[^\n]{0,39}\p{L}[^\n.!?]{0,39}\z/.freeze

      module_function

      def lines(text)
        lines = text.split("\n")
        joined(lines, joins(lines)) { |first, second| "#{first} #{second}" }.join("\n")
      end

      def blocks(blocks)
        joins = joins(blocks.map { |block| text(block) })
        joined(blocks, joins) { |first, second| join(first, second) }
      end

      # The blocks of sibling elements, one group each. Only a group of one
      # block takes the next group's first block onto its line: blocks of
      # elements apart on the page ("Tags:" with no tags, then a button in
      # the next box) stay apart.
      def siblings(groups)
        kept = []
        taken = false
        groups.each_with_index do |group, index|
          previous = groups[index - 1] if index.positive?
          taken = !taken && previous&.size == 1 && !group.empty? && sibling_join?(groups, index)
          if taken
            kept[-1] = join(kept[-1], group.first)
            kept.concat(group.drop(1))
          else
            kept.concat(group)
          end
        end
        kept
      end

      def sibling_join?(groups, index)
        before = index > 1 ? groups[index - 2].last : nil
        rest = groups[index, 3].flatten(1).drop(1).first(2)
        texts = [before, groups[index - 1].first, groups[index].first, *rest].map { |block| block && text(block) }
        joins(texts).include?(1)
      end

      def text(block)
        block.text if block.kind == :paragraph
      end

      def join(first, second)
        Block.new(:paragraph, "#{first.text} #{second.text}")
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

          unit?(texts, index) || (first.match?(LABEL) && second.match?(VALUE) && !list?(rest))
        end.to_set
      end

      def unit?(texts, index)
        first, second, third = texts[index, 3]
        return false unless first.match?(NUMBER) && second.match?(UNIT) && !third&.match?(NUMBER)

        before = texts[index - 1] if index.positive?
        before.nil? || before.match?(NUMBER) || !before.match?(NAME)
      end

      def list?(rest)
        rest.size == 2 && rest.all? { |text| !text.nil? && text.match?(VALUE) && !text.match?(/[:：]/) }
      end
    end
  end
end

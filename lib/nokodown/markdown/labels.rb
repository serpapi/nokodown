# frozen_string_literal: true

module Nokodown
  module Markdown
    # A label and its value, or a number and its unit, that a page sets on
    # lines or in blocks of their own ("Type:" over "Condo", "27" over
    # "Nov") read as one line. A label over three or more short lines
    # introduces a list ("Check all that apply:") and stays on its own. In a
    # run of numbers and names that take turns, the first decides how they
    # pair: numbers first are counts or badges of the names after them;
    # names first take the numbers after them as values ("Loft" over "440"
    # over "Stories" over "1.5").
    module Labels
      LABEL = /\A[^\s#>|`\-\d!][^\n]{0,38}[:：]\**\z/.freeze
      NUMBER = /\A\d[\d.,]{0,7}\z/.freeze
      VALUE = /\A(?!!\[)[^\s#>|`\-](?![^\n]*[:：]\**\z)[^\n]{0,59}\z/.freeze
      # A unit, not a label of its own or a sentence: "3" over "Baths:" or
      # over "Pick a page." is a number beside them, not their count.
      UNIT = /\A\p{L}[^\n]{0,29}(?<![.!?。！？:：*])\z/.freeze
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
      # block takes the next group's one block onto its line: blocks of
      # elements apart on the page ("Tags:" with no tags, then a button in
      # the next box) stay apart.
      def siblings(groups)
        joins = joins(groups.map { |group| text(group.first) if group.size == 1 })
        joined(groups, joins) { |first, second| [join(first.first, second.first)] }.flatten(1)
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
        starts = []
        texts.each_index.select do |index|
          starts[index] = run_start(texts, index, starts)
          first, second, *rest = texts[index, 4]
          next false if first.nil? || second.nil?

          unit?(texts, index, starts) || (first.match?(LABEL) && value?(second, rest.first) && !list?(rest))
        end.to_set
      end

      # A line typed with a bullet, or with a number the next line counts on
      # from, is an item of a list the label introduces; a number alone is
      # the value ("Datum:" over "10. Oktober 2023").
      def value?(text, following)
        return false unless text.match?(VALUE) && !text.match?(Lists::GLYPH)

        number = text[Lists::TYPED_NUMBER, 1]
        number.nil? || following.to_s[Lists::TYPED_NUMBER, 1].to_i != number.to_i + 1
      end

      def unit?(texts, index, starts)
        return false unless texts[index].match?(NUMBER) && texts[index + 1].match?(UNIT)

        start = starts[index]
        !(start.positive? && name?(texts[start - 1]))
      end

      # Where the run of numbers and names that a number ends begins.
      def run_start(texts, index, starts)
        number = index >= 2 && texts[index]&.match?(NUMBER) && texts[index - 2]&.match?(NUMBER)
        number && name?(texts[index - 1]) ? starts[index - 2] : index
      end

      def name?(text)
        !text.nil? && !text.match?(NUMBER) && text.match?(NAME)
      end

      def list?(rest)
        rest.size == 2 && rest.all? { |text| !text.nil? && text.match?(VALUE) && !text.match?(/[:：]/) }
      end
    end
  end
end

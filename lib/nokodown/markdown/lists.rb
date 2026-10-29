# frozen_string_literal: true

module Nokodown
  module Markdown
    # Lists the page wrote as something else. Sites type a glyph before each
    # line instead of writing a list ("• Fast", "✓ Free shipping"), and split
    # a numbered list into one element per item.
    module Lists
      # Any pictograph serves as a bullet ("🔹 Retargeting"), and so does a
      # typed asterisk; a dash opens the lines of a dialogue too. Pages in
      # scripts written without spaces set the bullet right before the item
      # ("・送料無料").
      CLOSE_BULLETS = "・･·•●○◆◇■□▪★☆▶►"
      GLYPH = /
        \A(\\\*|[#{Renderer::GLYPHS}◽◾]|#{Text::PICTOGRAPH})\uFE0F?
        (?:\s+|(?<=[#{CLOSE_BULLETS}])(?=[^\s\p{So}\p{Sm}・･·•]))
      /x.freeze
      NUMBER = /^(\d+)\. /.freeze
      FIRST_NUMBER = /\A(\d+)\. /.freeze
      # "1.", "1)" and the "1、" of Chinese and Japanese pages.
      TYPED_NUMBER = /\A(\d{1,3})(?:[.)．]\s+|、\s*)/.freeze
      # A cross or a no-entry sign says what a line is not.
      NEGATIVE = /[❌❎✕✖✗✘🚫⛔]/.freeze
      LABEL = /[:：]\z/.freeze
      MARKER = "\\d{1,9}[.)]|[-+*]"
      # Text that opens a list item at a line's start.
      LIST_ITEM = /\A(?:#{MARKER})(?:\s|\z)/.freeze
      # An item's text that would open a list of its own, or a task.
      MARKED_TEXT = /\A- (?:#{MARKER}|\[[ xX]\])(?:\s|\z)/.freeze

      module_function

      def call(blocks)
        joined(numbered(typed(blocks)))
      end

      # Paragraphs whose lines all open with the same glyph become one list,
      # unless paragraphs with another glyph sit beside them, as cons marked
      # ✗ after pros marked ✓. A label marked with another glyph ("■
      # Features:") introduces the list.
      def typed(blocks)
        blocks = blocks.flat_map { |block| introduced(block) }
        runs = blocks.slice_when { |a, b| glyph(a).nil? || glyph(a) != glyph(b) }.to_a
        runs.each_with_index.flat_map do |run, index|
          neighbours = [index.positive? ? runs[index - 1].last : nil, runs[index + 1]&.first].compact
          typed_list?(run, neighbours) ? [list(run)] : run.map { |block| bare_label(block) }
        end
      end

      # A glyph before a label ("■ Features:") only decorates it; a typed
      # asterisk marks a footnote.
      def bare_label(block)
        return block unless glyph(block) && glyph(block) != "\\*" && label?(block)

        Block.new(:paragraph, Text.escape_line_starts(block.text.sub(GLYPH, "")))
      end

      def label?(block)
        block.text.match?(LABEL) && !block.text.include?("\n")
      end

      def typed_list?(run, neighbours)
        return false if glyph(run.first).nil? || glyph(run.first).match?(NEGATIVE)
        return false if neighbours.any? { |block| glyph(block) && !label?(block) }

        run.sum { |block| block.text.count("\n") + 1 } > 1
      end

      def list(run)
        lines = run.flat_map { |block| block.text.split("\n") }
        Block.new(:list, lines.map { |line| "- #{Text.escape_line_starts(line.sub(GLYPH, ''))}" }.join("\n"))
      end

      # A line that introduces the glyph lines below it in one paragraph
      # ("Features:" over "• Fast" and "• Safe") stays a line of its own.
      def introduced(block)
        return [block] unless block.kind == :paragraph

        first, rest = block.text.split("\n", 2)
        return [block] if rest.nil? || !rest.include?("\n") || first.match?(GLYPH)

        items = Block.new(:paragraph, rest)
        glyph(items) ? [Block.new(:paragraph, first), items] : [block]
      end

      # Paragraphs whose lines count up ("1、", "2、") are a numbered list.
      def numbered(blocks)
        counts = blocks.map { |block| counts(block) }
        runs = blocks.each_index.slice_when { |a, b| !counts[a] || !counts[b] || counts[b].first != counts[a].last + 1 }
        runs.flat_map do |run|
          lines = run.flat_map { |index| blocks[index].text.split("\n") }
          counts[run.first] && lines.size > 1 ? [numbered_list(lines)] : blocks.values_at(*run)
        end
      end

      def counts(block)
        return unless block.kind == :paragraph

        numbers = block.text.split("\n").map { |line| line[TYPED_NUMBER, 1]&.to_i }
        numbers if numbers.any? && numbers.all? && numbers.each_cons(2).all? { |a, b| b == a + 1 }
      end

      def numbered_list(lines)
        items = lines.map do |line|
          "#{line[TYPED_NUMBER, 1].to_i}. #{Text.escape_line_starts(line.sub(TYPED_NUMBER, ''))}"
        end
        Block.new(:list, items.join("\n"))
      end

      # The glyph that opens every line of a paragraph, or nil.
      def glyph(block)
        return unless block.kind == :paragraph

        glyphs = block.text.split("\n").map { |line| line[GLYPH, 1] }
        glyphs.first if glyphs.uniq.size == 1
      end

      # Numbered lists whose numbering runs on. Bulleted lists side by side
      # stay apart: the blank line is all that tells their groups apart.
      def joined(blocks)
        blocks.each_with_object([]) do |block, kept|
          previous = kept.last
          if previous && continues?(previous, block)
            kept[-1] = Block.new(:list, "#{previous.text}\n#{block.text}")
          else
            kept << block
          end
        end
      end

      def continues?(previous, block)
        return false unless previous.kind == :list && block.kind == :list && block.text.match?(FIRST_NUMBER)

        last = previous.text.scan(NUMBER).last
        !last.nil? && block.text[FIRST_NUMBER, 1].to_i == last.first.to_i + 1
      end

      # Sites wrap a date or a tag in a list of its own, and each entry of a
      # directory in one. A blank line between items of one groups nothing,
      # so side by side they are one list, and alone, beside no other list
      # or text that opens one, the item is a line of text, unless its text
      # would read as a list item or a task there ("1. Read it aloud.").
      # Runs last, once the cards CardLinks reads are settled.
      def single_items(blocks)
        runs = blocks.each_index.chunk_while { |a, b| single_item?(blocks[a]) && single_item?(blocks[b]) }
        runs.flat_map do |run|
          first = blocks[run.first]
          next blocks.values_at(*run) unless single_item?(first)
          next [Block.new(:list, run.map { |index| blocks[index].text }.join("\n"))] if run.size > 1
          next [first] if beside_list?(blocks, run.first) || first.text.match?(MARKED_TEXT)

          [Block.new(:paragraph, first.text.delete_prefix("- "))]
        end
      end

      def single_item?(block)
        block.kind == :list && block.text.start_with?("- ") && !block.text.include?("\n")
      end

      def beside_list?(blocks, index)
        [index.positive? ? blocks[index - 1] : nil, blocks[index + 1]].compact.any? do |block|
          block.kind == :list || (block.kind == :paragraph && block.text.match?(LIST_ITEM))
        end
      end
    end
  end
end

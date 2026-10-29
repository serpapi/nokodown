# frozen_string_literal: true

module Nokodown
  module Markdown
    # Lists the page wrote as something else. Sites type a glyph before each
    # line instead of writing a list ("• Fast", "✓ Free shipping"), and split
    # a numbered list into one element per item.
    module Lists
      GLYPH = /\A([#{Renderer::GLYPHS}✓✔✅☑➢◆★])\s+/.freeze
      NUMBER = /^(\d+)\. /.freeze
      FIRST_NUMBER = /\A(\d+)\. /.freeze

      module_function

      def call(blocks)
        joined(typed(blocks))
      end

      # Paragraphs whose lines all open with the same glyph become one list,
      # unless paragraphs with another glyph sit beside them, as cons marked
      # ✗ after pros marked ✓.
      def typed(blocks)
        runs = blocks.slice_when { |a, b| glyph(a).nil? || glyph(a) != glyph(b) }.to_a
        runs.each_with_index.flat_map do |run, index|
          neighbours = [index.positive? ? runs[index - 1].last : nil, runs[index + 1]&.first].compact
          typed_list?(run, neighbours) ? [list(run)] : run
        end
      end

      def typed_list?(run, neighbours)
        return false if glyph(run.first).nil? || neighbours.any? { |block| glyph(block) }

        run.sum { |block| block.text.count("\n") + 1 } > 1
      end

      def list(run)
        lines = run.flat_map { |block| block.text.split("\n") }
        Block.new(:list, lines.map { |line| "- #{Text.escape_line_starts(line.sub(GLYPH, ''))}" }.join("\n"))
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
    end
  end
end

# frozen_string_literal: true

module Nokodown
  module Markdown
    # Sites type a glyph before each line instead of writing a list: "• Fast",
    # "✓ Free shipping". Paragraphs whose lines all open with the same glyph
    # become one list, unless paragraphs with another glyph sit beside them,
    # as cons marked ✗ after pros marked ✓.
    module TypedLists
      GLYPH = /\A([#{Renderer::GLYPHS}✓✔✅☑➢◆★])\s+/.freeze

      module_function

      def call(blocks)
        runs = blocks.slice_when { |a, b| glyph(a).nil? || glyph(a) != glyph(b) }.to_a
        runs.each_with_index.flat_map do |run, index|
          neighbours = [index.positive? ? runs[index - 1].last : nil, runs[index + 1]&.first].compact
          typed_list?(run, neighbours) ? [list(run)] : run
        end
      end

      def typed_list?(run, neighbours)
        !glyph(run.first).nil? && run.sum { |block| block.text.count("\n") + 1 } > 1 && neighbours.none? { |block| glyph(block) }
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
    end
  end
end

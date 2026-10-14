# frozen_string_literal: true

module Nokodown
  module Markdown
    # Block-level tidying after rendering: repeated blocks, stray rules,
    # punctuation-only lines and section headings left without a section.
    module Cleanup
      DEDUPE_WINDOW = 4
      IMAGE_ONLY = /\A!\[([^\]]*)\]\([^)]*\)\z/.freeze

      module_function

      def call(blocks)
        blocks = blocks.reject { |block| noise?(block) }
        blocks = dedupe(blocks)
        blocks = trim_rules(blocks)
        drop_empty_sections(blocks)
      end

      def noise?(block)
        return false unless block.kind == :paragraph

        text = block.text
        return true unless text.match?(/[\p{L}\p{N}]/) || text.include?("](")

        plain = text.gsub(/[*_`~]/, "").strip
        plain.length <= 80 && plain.match?(Patterns::BOILERPLATE_TEXT)
      end

      # Responsive and "enlarge" variants repeat an image (and its caption) a
      # block or two later, within the same section. Dropping the image makes
      # the captions adjacent.
      def dedupe(blocks)
        blocks.each_with_object([]) do |block, kept|
          window = block.text.match?(IMAGE_ONLY) ? same_section(kept.last(DEDUPE_WINDOW)) : kept.last(1)
          kept << block unless window.any? { |previous| identity(previous) == identity(block) }
        end
      end

      def same_section(blocks)
        heading = blocks.rindex { |block| block.kind == :heading }
        heading ? blocks.drop(heading + 1) : blocks
      end

      # Variants of one image differ in URL (size, crop) but share alt text.
      def identity(block)
        alt = block.text[IMAGE_ONLY, 1]
        alt && alt.length >= 10 ? "image:#{alt}" : block.text
      end

      def trim_rules(blocks)
        blocks = blocks.each_with_object([]) do |block, kept|
          next if block.kind == :rule && (kept.empty? || kept.last.kind == :rule || kept.last.kind == :heading)

          kept << block
        end
        blocks.pop while blocks.last&.kind == :rule
        blocks
      end

      # A heading followed by nothing, or by a heading at the same or a higher
      # level, lost its section during extraction.
      def drop_empty_sections(blocks)
        kept = []
        blocks.each_with_index do |block, index|
          if block.kind == :heading
            following = blocks[(index + 1)..].find { |b| b.kind != :rule }
            empty = following.nil? || (following.kind == :heading && following.level <= block.level)
            next if empty && (following.nil? || heading_text(block).match?(Patterns::NOISE_HEADING))
          end
          kept << block
        end
        kept.pop while kept.last&.kind == :heading
        kept
      end

      def heading_text(block)
        block.text.sub(/\A#+\s*/, "").gsub(/\[([^\]]*)\]\([^)]*\)/, '\1').gsub(/[*_`]/, "")
      end
    end
  end
end

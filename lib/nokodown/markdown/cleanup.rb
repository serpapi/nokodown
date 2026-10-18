# frozen_string_literal: true

module Nokodown
  module Markdown
    # Block-level tidying after rendering: repeated blocks, stray rules,
    # punctuation-only lines and section headings left without a section.
    module Cleanup
      DEDUPE_WINDOW = 4
      IMAGE_ONLY = /\A!\[([^\]]*)\]\([^)]*\)\z/.freeze
      LINKED_HEADING = /\A#+ \[.*\]\(.*\)\z/.freeze
      TITLE_LIST_MIN = 3

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
      # level, lost its section during extraction. Title lists are content in
      # their own right, and a page that is only its headline keeps it.
      def drop_empty_sections(blocks)
        titles = title_list_indexes(blocks)
        kept = blocks.each_index.reject { |index| !titles.include?(index) && empty_section?(blocks, index) }
        kept.pop while kept.any? && blocks[kept.last].kind == :heading && !titles.include?(kept.last)
        return blocks.values_at(*kept) if kept.any?

        [blocks.find { |block| block.kind == :heading && block.level == 1 }].compact
      end

      def empty_section?(blocks, index)
        block = blocks[index]
        return false unless block.kind == :heading

        following = blocks[(index + 1)..].find { |b| b.kind != :rule }
        return true if following.nil?
        return false unless following.kind == :heading && following.level <= block.level

        heading_text(block).match?(Patterns::NOISE_HEADING)
      end

      # Same-level headings in a row, mostly links, are the titles of cards
      # whose details were removed (products, related guides), not sections.
      # A "Trending" or "Related" heading among them is still a section label.
      def title_list_indexes(blocks)
        runs = blocks.each_index.reject { |index| blocks[index].kind == :rule }.slice_when do |a, b|
          blocks[a].kind != :heading || blocks[b].kind != :heading || blocks[a].level != blocks[b].level
        end
        indexes = runs.select { |run| title_list?(blocks.values_at(*run)) }.flatten
        indexes.reject { |index| heading_text(blocks[index]).match?(Patterns::NOISE_HEADING) }.to_set
      end

      def title_list?(headings)
        return false if headings.size < TITLE_LIST_MIN

        headings.count { |heading| heading.text.match?(LINKED_HEADING) } * 2 > headings.size
      end

      def heading_text(block)
        block.text.sub(/\A#+\s*/, "").gsub(/\[([^\]]*)\]\([^)]*\)/, '\1').gsub(/[*_`]/, "")
      end
    end
  end
end

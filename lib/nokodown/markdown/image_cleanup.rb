# frozen_string_literal: true

module Nokodown
  module Markdown
    # The last step of Cleanup: removes redundant images and repeats of an
    # image anywhere on the page. Run earlier, it would leave a heading whose
    # section held only an image for drop_empty_sections to take.
    class ImageCleanup
      # A line with nothing but list or quote markers.
      BARE_LINE = /\A[\s>]*(?:(?:[-*+]|\d+\.)\s*)?\z/.freeze
      LIST_MARKER = /\A *(?:[-*+]|\d+\.) /.freeze

      def initialize(images)
        @images = images
        @pattern = Regexp.union(images.keys)
        @seen = Set.new
      end

      def call(blocks)
        blocks.select do |block|
          next true if block.kind == :code || !block.text.match?(@pattern)

          text = without_images(block.text)
          next true if text == block.text

          block.text = text
          text.match?(/[\p{L}\p{N}]/) && !Cleanup.noise?(block)
        end
      end

      private

      def without_images(text)
        lines = text.split("\n").map { |line| [line, line_without_images(line)] }
        drop_bare_lines(lines).join("\n").gsub(/\n{3,}/, "\n\n").strip
      end

      def line_without_images(line)
        alone = line.gsub(@pattern, "").match?(BARE_LINE)
        kept = line.gsub(@pattern) { |markup| keep?(@images[markup], alone) ? markup : "" }
        return line if kept == line

        indent = line[/\A */]
        indent + kept[indent.length..].strip.squeeze(" ")
      end

      # A repeat goes only when it stands alone on its line: beside text, as
      # in a table of tick marks or a row of rating stars, each copy counts.
      def keep?(image, alone)
        return false if image.redundant

        first_copy = !@seen.add?(image.url).nil?
        first_copy || !alone
      end

      # Lines left with only markers go. A list item whose first line held
      # only images starts at its next line instead.
      def drop_bare_lines(lines)
        marker = nil
        lines.filter_map do |line, kept|
          if kept != line && kept.match?(BARE_LINE)
            marker = line[LIST_MARKER] || marker
            next
          end
          next kept if kept.empty?

          kept = marker + kept[marker.length..] if marker && continues_item?(kept, marker)
          marker = nil
          kept
        end
      end

      # Indented to the item's text, and not a nested list.
      def continues_item?(line, marker)
        line.start_with?(" " * marker.length) && !line[marker.length..].match?(/\A(?:\s|[-*+] |\d+\. )/)
      end
    end
  end
end

# frozen_string_literal: true

module Nokodown
  module Markdown
    # The last step of Cleanup: removes redundant images and repeats of an
    # image anywhere on the page. Run earlier, it would leave a heading whose
    # section held only an image for drop_empty_sections to take.
    class ImageCleanup
      # Markup as Inline writes it: "](" in the alt is escaped, and the
      # destination's parentheses are balanced or percent-encoded. One pattern
      # for every image keeps the cost linear on pages with thousands; the
      # rare URL with nested parentheses is not matched, so its image stays.
      IMAGE = /!\[(?:\\.|[^\\\]\n]|\](?!\())*\]\((?:[^()\s]|\([^()\s]*\))*\)/.freeze
      DESTINATION = /\]\(((?:[^()\s]|\([^()\s]*\))*)\)/.freeze
      # A line with nothing but list or quote markers, nested lists included.
      BARE_LINE = /\A(?:\s|>|[-*+]|\d+\.)*\z/.freeze
      LIST_MARKER = /\A *(?:[-*+]|\d+\.) /.freeze
      # The indentation and markers before a line's text.
      LINE_PREFIX = /\A(?: |>|(?:[-*+]|\d+\.) )*/.freeze

      def initialize(images)
        @images = images
        @seen = Set.new
      end

      def call(blocks)
        @linked = linked_pages(blocks)
        blocks.select do |block|
          next true if block.kind == :code || !block.text.include?("![")

          text = without_images(block.text)
          next true if text == block.text

          block.text = text
          text.match?(/[\p{L}\p{N}]/) && !Cleanup.noise?(block)
        end
      end

      private

      # Pages the final Markdown still links to.
      def linked_pages(blocks)
        destinations = blocks.reject { |block| block.kind == :code }.flat_map { |block| block.text.scan(DESTINATION).flatten }
        Set.new(destinations.map { |destination| RedundantImages.page(destination) })
      end

      def without_images(text)
        lines = text.split("\n").map { |line| [line, line_without_images(line)] }
        drop_bare_lines(lines).join("\n").gsub(/\n{3,}/, "\n\n").strip
      end

      # Text that followed a removed image can now start the line, where "#"
      # or ">" would turn it into a heading or a quote.
      def line_without_images(line)
        alone = line.gsub(IMAGE) { |markup| @images.key?(markup) ? "" : markup }.match?(BARE_LINE)
        kept = line.gsub(IMAGE) { |markup| keep?(markup, alone) ? markup : "" }
        return line if kept == line

        prefix = line[LINE_PREFIX]
        prefix + Text.escape_line_starts(kept[prefix.length..].strip.squeeze(" "))
      end

      # A repeat goes only when it stands alone on its line: beside text, as
      # in a table of tick marks or a row of rating stars, each copy counts.
      def keep?(markup, alone)
        image = @images[markup]
        return true if image.nil?
        return false if redundant?(image)

        first_copy = !@seen.include?(image.url)
        @seen << image.url
        first_copy || !alone
      end

      # A thumbnail goes only while the Markdown still links to its page; a
      # card whose title link was dropped keeps its image.
      def redundant?(image)
        image.redundant && image.targets.all? { |target| @linked.include?(target) }
      end

      # Lines left with only markers go. A list item whose first line held
      # only images starts at its next line instead.
      def drop_bare_lines(lines)
        marker = nil
        lines.filter_map do |line, kept|
          if kept != line && kept.match?(BARE_LINE)
            marker = pending_marker(line, marker)
            next
          end
          next kept if kept.empty?

          kept = marker + kept[marker.length..] if marker && continues_item?(kept, marker)
          marker = nil
          kept
        end
      end

      # The outermost item still waiting for its text: a bare line nested in
      # it, such as a list of thumbnails, does not take its place.
      def pending_marker(line, marker)
        return marker if marker && line.start_with?(" " * marker.length)

        line[LIST_MARKER] || marker
      end

      # Indented to the item's text, not deeper.
      def continues_item?(line, marker)
        line.start_with?(" " * marker.length) && !line[marker.length..].match?(/\A\s/)
      end
    end
  end
end

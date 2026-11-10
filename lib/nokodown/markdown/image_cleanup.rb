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
      IMAGE = /!\[(?:\\.|[^\\\[\]\n]|\[(?:\\.|[^\\\[\]\n])*\])*\]\((?:[^()\s]|\([^()\s]*\))*\)/.freeze
      DESTINATION = /\]\(((?:[^()\s]|\([^()\s]*\))*)\)/.freeze
      # A line with nothing but list or quote markers, nested lists included.
      BARE_LINE = /\A(?:\s|>|[-*+]|\d+\.)*\z/.freeze
      LIST_MARKER = /\A *(?:[-*+]|\d+\.) /.freeze
      LIST_MARKERS = /\A *(?:(?:[-*+]|\d+\.) )+/.freeze
      # The indentation and markers before a line's text.
      LINE_PREFIX = /\A(?: |>|(?:[-*+]|\d+\.) )*/.freeze
      # Text starts a line with ``` only to open a code span, closed later on
      # the line (Text.escape_line_starts), so a run with no backtick after
      # it is the fence of a code block nested in a list or a quote.
      FENCE = /#{LINE_PREFIX.source}(`{3,})(?=[^`]*\z)/.freeze

      def initialize(images)
        @images = images
        # Image URL => @text_lines when its last copy was written.
        @seen = {}
        @text_lines = 0
      end

      def call(blocks)
        @linked = linked_pages(blocks)
        blocks.select do |block|
          if block.kind == :code || !block.text.include?("![")
            @text_lines += 1
            next true
          end

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
        lines = with_code_flags(text.split("\n")).map do |line, code|
          next [line, line_without_images(line), false] unless code

          @text_lines += 1
          [line, line, true]
        end
        squeeze(drop_bare_lines(lines)).strip
      end

      # Each line, and whether it belongs to a nested code block, whose lines
      # stay as they are.
      def with_code_flags(lines)
        fence = nil
        lines.map do |line|
          run = line[FENCE, 1]
          if fence
            fence = nil if run && run.length >= fence.length
            next [line, true]
          end
          fence = run
          [line, !run.nil?]
        end
      end

      # Text that followed a removed image can now start the line, where "#"
      # or ">" would turn it into a heading or a quote.
      def line_without_images(line)
        removed = removed_images(line)
        return line if removed.empty?

        kept = line.gsub(IMAGE) { |markup| removed.include?(markup) ? " " : markup }
        prefix = line[LINE_PREFIX]
        prefix + Text.escape_line_starts(kept[prefix.length..].strip.squeeze(" "))
      end

      # Redundant images, and later copies of an image standing alone on its
      # line. Beside text, as in a table of tick marks, each copy counts.
      def removed_images(line)
        markups = line.scan(IMAGE).select { |markup| @images.key?(markup) }
        content = markups.reject { |markup| redundant?(@images[markup]) }
        alone = line.gsub(IMAGE) { |markup| @images.key?(markup) ? "" : markup }.match?(BARE_LINE)
        removed = Set.new(markups - content)
        removed.merge(repeats(content)) if alone
        content.each { |markup| @seen[@images[markup].url] = @text_lines }
        @text_lines += 1 unless alone
        removed
      end

      # A line with several copies of one image is a count, such as a row of
      # rating stars, and keeps them all. Otherwise a copy without alt text
      # adds nothing. One with alt text can mark its own item (an award, a
      # verified tick), so it goes only when nothing but images came since
      # the last copy, as in a logo strip shown twice.
      def repeats(content)
        urls = content.map { |markup| @images[markup].url }
        return [] if urls.uniq.size < urls.size

        content.select do |markup|
          seen = @seen[@images[markup].url]
          seen && (markup.start_with?("![]") || seen == @text_lines)
        end
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
        lines.filter_map do |line, kept, code|
          if kept != line && kept.match?(BARE_LINE)
            marker = pending_marker(line, marker)
            next
          end
          next [kept, code] if kept.empty?

          kept = with_marker(kept, marker) if marker
          marker = nil
          [kept, code]
        end
      end

      # One blank line where dropped lines left several, except in code.
      def squeeze(lines)
        lines.each_with_object([]) do |(line, code), kept|
          kept << line unless !code && line.empty? && kept.last == ""
        end.join("\n")
      end

      # The outermost item still waiting for its text: a bare line nested in
      # it, such as a list of thumbnails, does not take its place.
      def pending_marker(line, marker)
        return marker if marker && line.start_with?(" " * marker[LIST_MARKER].length)

        line[LIST_MARKERS] || marker
      end

      # The markers of the items the line is indented into, not deeper.
      def with_marker(line, marker)
        prefixes = marker.scan(/ *(?:[-*+]|\d+\.) /).each_with_object([]) { |piece, all| all << "#{all.last}#{piece}" }
        prefix = prefixes.reverse.find { |candidate| line.start_with?(" " * candidate.length) && !line[candidate.length..].match?(/\A\s/) }
        prefix ? prefix + line[prefix.length..] : line
      end
    end
  end
end

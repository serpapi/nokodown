# frozen_string_literal: true

module Nokodown
  module Markdown
    # Text a page says twice: copies of the title, labels over the heading
    # they repeat, tab strips listing the headings below, and the same block
    # twice in a row once images between them are gone. Runs once the title
    # is in place.
    module Repeats
      # Blocks around the title where a part of it ("Site" in "Page - Site")
      # is still the title.
      TITLE_HEAD = 8
      TITLE_SEPARATOR = /\s+[-|–—:·•»]\s+|\s*[|｜]\s*/.freeze
      LABEL_WORDS = 5
      LABEL_LENGTH = 40
      ECHO_WINDOW = 4
      LIST_ITEM = /\A\s*(?:[-*+]|\d+\.)\s+(.*)\z/.freeze
      LINK_TARGET = /\]\(([^)\s]*)/.freeze

      module_function

      def call(blocks)
        blocks = drop_title_copies(blocks)
        blocks = drop_heading_echoes(blocks)
        blocks = drop_heading_lists(blocks)
        drop_adjacent_copies(blocks)
      end

      # Headings and paragraphs that say only what the H1 says, wherever
      # they are; near the H1 also the parts of a "Page - Site" title. A
      # paragraph linking elsewhere, such as an embedded video named like
      # the page, adds its destination, and so does a linked heading away
      # from the H1, such as a card for a variant of the same product.
      def drop_title_copies(blocks)
        index = blocks.index { |block| block.kind == :heading && block.level == 1 }
        return blocks unless index

        heading = Cleanup.heading_text(blocks[index])
        title = squash(heading)
        return blocks if title.empty?

        parts = title_parts(heading)
        blocks.reject.with_index do |block, position|
          near = (position - index).abs <= TITLE_HEAD
          text = position == index ? nil : title_text(block, near)
          next false if text.nil? || text.empty? || section_content?(blocks, position) || runs_on?(blocks, position)

          text == title || (block.kind == :paragraph && near && parts.include?(text))
        end
      end

      def title_text(block, near)
        return unless %i[heading paragraph].include?(block.kind)
        return if block.text.include?("](") && (block.kind == :paragraph || !near)

        squash(block.kind == :heading ? Cleanup.heading_text(block) : block.text)
      end

      def title_parts(heading)
        parts = heading.split(TITLE_SEPARATOR).map { |part| squash(part) }.reject(&:empty?)
        parts.size > 1 ? parts.to_set : Set.new
      end

      # A paragraph repeating a heading just above is the same title
      # rendered twice, unless it links elsewhere.
      def drop_heading_echoes(blocks)
        blocks.reject.with_index do |block, index|
          next false unless block.kind == :paragraph && !block.text.include?("![")

          text = Text.plain(block.text)
          next true if repeats_heading_below?(blocks, index, text)

          !block.text.include?("](") && !section_content?(blocks, index) && !runs_on?(blocks, index) &&
            repeats_heading_above?(blocks, index, squash(text))
        end
      end

      # A line that runs on into the next, like the first line of a poem
      # that gives the poem its name, is part of the text.
      def runs_on?(blocks, index)
        return false unless blocks[index].kind == :paragraph

        following = blocks[index + 1]
        Text.plain(blocks[index].text).match?(/[,;:–—-]\z/) ||
          (following&.kind == :paragraph && Text.plain(following.text).match?(/\A\p{Ll}/))
      end

      # A paragraph that is all a section below the title holds ("### Tag",
      # then the tag) stays, so its heading is not left empty.
      def section_content?(blocks, index)
        previous = index.positive? ? blocks[index - 1] : nil
        return false unless blocks[index].kind == :paragraph && previous&.kind == :heading && previous.level > 1

        following = blocks[index + 1]
        following.nil? || (following.kind == :heading && following.level <= previous.level)
      end

      # A short label over a heading that contains it ("About" over "About
      # Jo") is an eyebrow or a tab, and text of any length equal to the
      # heading below is that title rendered twice, unless it links to a page
      # the heading does not. A label right under a heading of the same level
      # or deeper is that section's content.
      def repeats_heading_below?(blocks, index, text)
        following = blocks[index + 1]
        following = blocks[index + 2] if following&.kind == :rule
        return false unless following&.kind == :heading && !squash(text).empty?

        previous = index.positive? ? blocks[index - 1] : nil
        return false if previous&.kind == :heading && previous.level >= following.level

        heading = Cleanup.heading_text(following)
        return copy_of?(blocks[index], following) && !runs_on?(blocks, index) if squash(heading) == squash(text)
        return false if text.length > LABEL_LENGTH || words(text).size > LABEL_WORDS || text.match?(/[.!?]\z/)

        contains_words?(words(heading), words(text))
      end

      def copy_of?(paragraph, heading)
        (paragraph.text.scan(LINK_TARGET) - heading.text.scan(LINK_TARGET)).empty?
      end

      def repeats_heading_above?(blocks, index, text)
        return false if text.empty?

        blocks[[0, index - ECHO_WINDOW].max...index].any? do |block|
          block.kind == :heading && squash(Cleanup.heading_text(block)) == text
        end
      end

      # A list whose every item is a heading of the page is a table of
      # contents or a strip of tabs.
      def drop_heading_lists(blocks)
        headings = blocks.select { |block| block.kind == :heading }.map { |block| squash(Cleanup.heading_text(block)) }.to_set
        return blocks if headings.size < 2

        blocks.reject do |block|
          next false unless block.kind == :list

          items = block.text.split("\n").reject(&:empty?).map { |line| line[LIST_ITEM, 1] }
          items.size >= 2 && items.all? { |item| item && headings.include?(squash(item)) }
        end
      end

      # Removing images can leave a block next to its own copy, such as a
      # caption shown under a photo and its zoomed twin.
      def drop_adjacent_copies(blocks)
        blocks.each_with_object([]) do |block, kept|
          kept << block unless kept.last && kept.last.kind == block.kind && kept.last.text == block.text
        end
      end

      def squash(text)
        Text.plain(text).downcase.gsub(/[^\p{L}\p{N}]+/, "")
      end

      def words(text)
        Text.plain(text).downcase.scan(/[\p{L}\p{N}]+/)
      end

      def contains_words?(haystack, needle)
        !needle.empty? && haystack.each_cons(needle.size).any? { |run| run == needle }
      end
    end
  end
end

# frozen_string_literal: true

module Nokodown
  module Markdown
    # A page links one name to one address again and again: an author under
    # each post, a store beside each of its products. The address is written
    # at the first of those links, and the later ones keep their text. A
    # link with other text says something of its own about the address and
    # keeps it, as does a label the page links to several addresses
    # ("Official site", "More details"): each of its links gives its item's
    # address. Without links every link keeps only its text. A block left
    # with nothing worth reading goes.
    module LinkAddresses
      module_function

      def call(blocks, links:)
        lines = blocks.map { |block| link_lines(block) }
        labels = links ? labels(lines) : Set.new
        written = Set.new
        blocks.zip(lines).filter_map do |block, split|
          next block unless split

          text = split.map { |line, parts, found| found.empty? ? line : unlinked(parts, found, links && written, labels) }.join("\n")
          next block if text == block.text

          block.text = text
          block unless Cleanup.noise?(block)
        end
      end

      # Each line with its pieces and links (none in code), or nil for a
      # block without links.
      def link_lines(block)
        return if block.kind == :code || !block.text.include?("](")

        lines = block.text.split("\n", -1)
        code = CodeBlock.nested_code_lines(lines)
        lines.each_with_index.map do |line, number|
          code[number] || !line.include?("](") ? [line, nil, []] : [line, *LinkLine.split(line)]
        end
      end

      # The texts the page links to more than one address.
      def labels(lines)
        addresses = Hash.new { |all, text| all[text] = Set.new }
        lines.compact.each do |split|
          split.each { |_, _, found| found.each { |_, text, destination| addresses[key(text)] << destination } }
        end
        addresses.select { |_, found| found.size > 1 }.keys.to_set
      end

      # written: the address and text of each link so far, or false to
      # unlink every link.
      def unlinked(parts, found, written, labels)
        repeats = written ? found.reject { |_, text, destination| labels.include?(key(text)) || written.add?([destination, key(text)]) } : found
        repeats.empty? ? parts.join : LinkLine.join(parts, repeats.to_h { |segment, text, _| [segment, text] }, items: written)
      end

      def key(text)
        Text.plain(text).downcase
      end
    end
  end
end

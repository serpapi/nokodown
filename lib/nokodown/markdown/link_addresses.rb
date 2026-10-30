# frozen_string_literal: true

module Nokodown
  module Markdown
    # A page links one name to one address again and again: an author under
    # each post, a store beside each of its products. The address is written
    # at the first of those links, and the later ones keep their text. A
    # link with other text says something of its own about the address and
    # keeps it. Without links every link keeps only its text. This runs
    # last, so the link kept is one the Markdown still holds, and the steps
    # before it read the same links either way: a card's thumbnail goes
    # beside its title as it would with links.
    module LinkAddresses
      module_function

      def call(blocks, links:)
        written = Set.new
        blocks.each do |block|
          next if block.kind == :code || !block.text.include?("](")

          block.text = unlinked(block.text, links ? written : nil)
        end
      end

      # written: the address and text of each link so far, or nil to unlink
      # every link.
      def unlinked(text, written)
        lines = text.split("\n", -1)
        code = CodeBlock.nested_code_lines(lines)
        lines.each_with_index.map do |line, number|
          next line if code[number] || !line.include?("](")

          parts, found = LinkLine.split(line)
          repeats = found.reject { |_, link_text, destination| written&.add?([destination, Text.plain(link_text).downcase]) }
          repeats.empty? ? line : LinkLine.join(parts, repeats.to_h { |segment, link_text, _| [segment, link_text] })
        end.join("\n")
      end
    end
  end
end

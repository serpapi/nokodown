# frozen_string_literal: true

module Nokodown
  module Markdown
    Block = Struct.new(:kind, :text, :level)

    # Turns DOM nodes into Markdown blocks. Runs of inline content become
    # paragraphs; block elements are rendered by tag.
    class Renderer
      MAX_DEPTH = 400
      GLYPHS = "•·▪◦‣►▶▸➤→■●○"
      # A run of glyphs (●●●○○) is a rating, not a bullet.
      BULLET_GLYPH = /\A(?:[#{GLYPHS}](?![#{GLYPHS}])|[-–—](?=\s))\s*/.freeze
      # Any symbols before a space can be an item's marker (+ and - in pros
      # and cons, ✓ and ✗), not only the glyphs that are stripped.
      LEADING_SYMBOLS = /\A[^\p{L}\p{N}\s]+(?=\s)/.freeze
      SIGN_LENGTH = 3
      # Heading-anchor markup puts a permalink before or after the text.
      # A sign before a number is the heading's own: "§ 1 Geltungsbereich".
      PERMALINK = /\A[#¶§🔗]\s+(?!\d)|\s+[#¶§🔗]\z/.freeze
      # Characters of a paragraph that a section holds and a card does not.
      SECTION_TEXT = 80

      def initialize(urls, images: true, links: true, redundant_images: {}, main_content: false)
        @inline = Inline.new(urls, images: images, links: links, redundant_images: redundant_images,
                                   main_content: main_content)
        @links = links
        @depth = 0
        @contains_block = {}
        @in_cell = false
      end

      def render(nodes)
        nodes.flat_map { |node| block_level?(node) ? block(node) : children_blocks(node) }
      end

      def children_blocks(node)
        groups = []
        run = []
        node.children.each do |child|
          if block_level?(child)
            groups << paragraphs(run)
            run = []
            groups << block(child)
          else
            run << child
          end
        end
        groups << paragraphs(run)
        Labels.siblings(groups.reject(&:empty?))
      end

      def paragraphs(nodes)
        nodes.empty? ? [] : text_paragraphs(@inline.render(nodes))
      end

      # A data table's cell holds values, where a line of only a sign ("+",
      # "×", "—") is one; a longer one ("_____") still separates.
      def cell_blocks(cell)
        outer = @in_cell
        @in_cell = true
        @inline.in_cell(cell) { children_blocks(cell) }
      ensure
        @in_cell = outer
      end

      # Two or more <br> in a row separate paragraphs, as Readability treats them.
      def text_paragraphs(text)
        text.split(/[ \t]*\n[ \t]*\n\s*/).filter_map do |chunk|
          lines = Text.tidy(chunk).split("\n").filter_map { |line| Separators.line(line) || (line if sign?(line)) }
          chunk = Labels.lines(lines.join("\n").strip)
          next if chunk.empty?

          Block.new(:paragraph, Text.escape_line_starts(Text.unescape_lone(Emphasis.paragraph(chunk))))
        end
      end

      def sign?(line)
        @in_cell && line.length <= SIGN_LENGTH
      end

      def inline(nodes)
        @inline.render(nodes)
      end

      def rendered_images
        @inline.rendered_images
      end

      def block_level?(node)
        return false unless node.element?
        return true if Dom::BLOCK.include?(node.name)
        return CodeBlock.standalone?(node) if node.name == "code"

        contains_block?(node)
      end

      def contains_block?(node)
        key = Dom.key(node)
        return @contains_block[key] if key && @contains_block.key?(key)

        found = node.element_children.any? { |child| Dom::BLOCK.include?(child.name) || contains_block?(child) }
        @contains_block[key] = found if key
        found
      end

      private

      def block(node)
        return paragraphs([node]) if @depth > MAX_DEPTH

        @depth += 1
        begin
          render_block(node)
        ensure
          @depth -= 1
        end
      end

      def render_block(node)
        case node.name
        when "h1", "h2", "h3", "h4", "h5", "h6" then heading(node)
        when "ul", "ol", "menu", "dir" then list(node)
        when "li" then format_list([children_blocks(node)].reject(&:empty?), nil)
        when "blockquote" then quote(node)
        when "pre" then CodeBlock.prose?(node) ? children_blocks(node) : CodeBlock.render(node, CodeBlock.preformatted(node))
        when "code" then CodeBlock.render(node, node.content)
        when "table" then Table.new(self, node).blocks
        when "dl" then definition_list(node)
        when "hr" then []
        when "iframe" then embed(node)
        when "summary" then summary(node)
        when "a" then linked_blocks(node)
        else children_blocks(node)
        end
      end

      # Text that long is a paragraph some site wrapped in a heading tag.
      def heading(node)
        text = Emphasis.unwrap(Text.single_line(@inline.render(node.children, heading: true)))
        text = Text.unescape_lone(text.gsub(PERMALINK, ""))
        return [] if text.empty?
        return [Block.new(:paragraph, text)] if text.length > 300

        level = node.name[1].to_i
        [Block.new(:heading, "#{'#' * level} #{text}", level)]
      end

      def list(node)
        items = []
        list_children(node).each do |child|
          blocks = list_item(child)
          owner = list_owner(items, wrapped: child.name == "li") if sublist?(child, blocks)
          owner ? owner.concat(blocks) : items << blocks
        end
        items.reject!(&:empty?)
        start = node.name == "ol" ? Integer(node["start"].to_s, exception: false) || 1 : nil
        return sections(unlisted(items, start)) if sections_list?(items, start)

        format_list(items, start)
      end

      # Tab panels and accordions set whole sections in list items: two
      # headings of different names, each over text of its own. Their
      # headings stay headings, outside a list. A card repeats its one
      # title, the date under a card's excerpt heads at most an icon, and
      # a contact list heads a phone number.
      def sections?(blocks)
        names = blocks.each_cons(2).filter_map { |block, following| block.text.sub(/\A#+ /, "") if heads_text?(block, following) }
        return false if names.uniq.size < 2

        blocks.drop_while { |block| block.kind != :heading }.any? { |block| section_text?(block) }
      end

      def heads_text?(block, following)
        block.kind == :heading && following.kind != :heading && following.text.gsub(ImageCleanup::IMAGE, "").match?(/[\p{L}\p{N}]/)
      end

      def section_text?(block)
        %i[table list].include?(block.kind) || (block.kind == :paragraph && block.text.length >= SECTION_TEXT)
      end

      # An ordered list ranks its items, so each number goes on its item's
      # first heading ("## 4. Acme Drill"). An item without a heading has
      # nowhere to keep its number, and the list stays a list.
      def sections_list?(items, start)
        return false unless items.any? { |blocks| sections?(blocks) }

        start.nil? || items.all? { |blocks| blocks.any? { |block| block.kind == :heading } }
      end

      def unlisted(items, start)
        return items.flatten(1) unless start

        items.each_with_index.flat_map do |blocks, index|
          first = blocks.index { |block| block.kind == :heading }
          blocks.each_with_index.map { |block, position| position == first ? ranked(block, start + index) : block }
        end
      end

      # A site may type the number into the heading already.
      def ranked(heading, number)
        hashes, text = heading.text.split(" ", 2)
        text.match?(/\A#{number}\b/) ? heading : Block.new(:heading, "#{hashes} #{number}. #{text}", heading.level)
      end

      # A heading that ends the list heads nothing in it, as an API
      # reference's closing "Returns void", and is a line of its text.
      def sections(blocks)
        last = blocks.last
        last.kind == :heading ? blocks[0...-1] << item_paragraph(last.text.sub(/\A#+ /, "")) : blocks
      end

      # A nested list belongs to the item before it, also when a site wraps
      # it in an item of its own (<li>Parent</li><li><ul>…</ul></li>).
      def sublist?(node, blocks)
        return false unless node.element? && blocks.size == 1 && blocks.first.kind == :list
        return true if %w[ul ol].include?(node.name)

        node.name == "li" && node.element_children.all? { |child| %w[ul ol].include?(child.name) }
      end

      # The last item with text of its own; empty items (<br>, whitespace) and
      # items that open with a list cannot hold one. A wrapped list does not
      # join an item that ends with a list already, as cons after pros.
      def list_owner(items, wrapped:)
        owner = items.reverse_each.find(&:any?)
        owner if owner && owner.first.kind != :list && !(wrapped && owner.last.kind == :list)
      end

      def list_item(node)
        return paragraphs([node]) unless node.element?
        return children_blocks(node) if node.name == "li"

        block_level?(node) ? block(node) : paragraphs([node])
      end

      # Wrappers between a list and its items (<ul><div><li>) are transparent.
      def list_children(node)
        node.children.flat_map do |child|
          wrapper = child.element? && !%w[li ul ol].include?(child.name) && child.element_children.any? { |c| c.name == "li" }
          wrapper ? list_children(child) : [child]
        end
      end

      def format_list(items, start)
        typed = typed_bullet?(items)
        items = items.each_with_index.map { |blocks, index| without_typed_marker(blocks, typed, start && start + index) }
        items.reject!(&:empty?)
        return [] if items.empty?

        nested_only = items.map { |blocks| blocks.size == 1 && bulleted_list?(blocks.first) }
        rendered = items.each_with_index.map do |blocks, index|
          previous = index.positive? && nested_only[index - 1]
          list_entry(start ? "#{start + index}. " : "- ", item_blocks(blocks), nested_only[index] && !previous && !nested_only[index + 1])
        end
        [Block.new(:list, rendered.join("\n"))]
      end

      # Card grids put each title in a heading and a badge in a list of its
      # own ("- - Popular"); in a list item the marker already sets them
      # apart, as it does an item set in bold throughout.
      def item_blocks(blocks)
        first = blocks.first
        return [item_paragraph(Emphasis.unwrap(first.text))] if blocks.size == 1 && first.kind == :paragraph

        blocks.each_with_index.map do |block, index|
          if block.kind == :heading
            item_paragraph(block.text.sub(/\A#+ /, ""))
          elsif index.zero? && blocks.size > 1 && bulleted_list?(block) && !block.text.include?("\n")
            item_paragraph(block.text.delete_prefix("- "))
          else
            block
          end
        end
      end

      def item_paragraph(text)
        Block.new(:paragraph, Text.escape_line_starts(text))
      end

      # Markers that differ between items carry meaning, as in legends where
      # ● and ○ mean yes and no, or pros and cons with + and -; one glyph
      # throughout is the site's own bullet.
      def typed_bullet?(items)
        markers = items.filter_map { |blocks| leading_marker(blocks.first) }
        markers.size > 1 && markers.uniq.size == 1
      end

      def leading_marker(block)
        return unless block.kind == :paragraph

        (block.text[BULLET_GLYPH] || block.text[LEADING_SYMBOLS])&.strip
      end

      # Sites type their own bullet or number into items, which would repeat
      # the marker ("- • a", "2. 2. b").
      def without_typed_marker(blocks, typed_bullet, number)
        first = blocks.first
        return blocks unless first.kind == :paragraph

        text = typed_bullet ? first.text.sub(BULLET_GLYPH, "") : first.text
        text = text.sub(/\A#{number}[.)](?!\d)\s*/, "") if number
        return blocks if text == first.text

        rest = blocks.drop(1)
        text.empty? ? rest : [Block.new(:paragraph, Text.escape_line_starts(text))] + rest
      end

      # An item holding nothing but a bulleted list would print an empty
      # marker ("- - a"), so the nested items stand in for it. An item with
      # more content stays one item, so product cards keep their boundaries,
      # and numbered lists keep their numbering.
      def list_entry(marker, blocks, hoist = false)
        return blocks.first.text if hoist && marker == "- "

        indent_item(marker, join_item(blocks))
      end

      def bulleted_list?(block)
        block.kind == :list && block.text.start_with?("- ")
      end

      def indent_item(marker, body)
        first, *rest = body.split("\n", -1)
        indent = " " * marker.length
        ([marker + first.to_s] + rest.map { |line| line.empty? ? "" : indent + line }).join("\n")
      end

      # Blank lines inside or between items cost tokens and change nothing
      # for a reader: the indentation keeps an item's blocks together.
      def join_item(blocks)
        Labels.blocks(blocks).map(&:text).join("\n")
      end

      def quote(node)
        inner = children_blocks(node).map(&:text).join("\n\n")
        return [] if inner.strip.empty?

        [Block.new(:quote, inner.split("\n", -1).map { |line| line.empty? ? ">" : "> #{line}" }.join("\n"))]
      end

      # Definitions of one paragraph each go on their term's line, so spec
      # sheets stay one line per row; longer ones keep their paragraphs, lists
      # and code under the term.
      def definition_list(node)
        entries = definition_groups(node).map do |term, definitions|
          compact?(definitions) ? definition_line(term, definitions) : list_entry("- ", definition_item(term, definitions))
        end
        entries.empty? ? [] : [Block.new(:list, entries.join("\n"))]
      end

      # [term, [blocks of each <dd>]] pairs; a term may be nil or have no <dd>.
      def definition_groups(node)
        groups = []
        definition_items(node).each do |item|
          if item.name == "dt"
            term = Text.escape(Dom.text(item))
            groups << [term, []] unless term.empty?
          else
            blocks = children_blocks(item)
            next if blocks.empty?

            groups << [nil, []] if groups.empty?
            groups.last[1] << blocks
          end
        end
        groups
      end

      def compact?(definitions)
        definitions.all? { |blocks| blocks.size == 1 && blocks.first.kind == :paragraph }
      end

      def definition_line(term, definitions)
        text = definitions.map { |blocks| Text.single_line(blocks.first.text) }.join("; ")
        return "- #{text}" if term.nil?
        return "- **#{term}**" if text.empty?

        term.match?(/[:：]\z/) ? "- **#{term}** #{text}" : "- **#{term}**: #{text}"
      end

      def definition_item(term, definitions)
        blocks = definitions.flatten(1)
        term ? [Block.new(:paragraph, "**#{term}**")] + blocks : blocks
      end

      def definition_items(node)
        node.element_children.flat_map do |child|
          case child.name
          when "dt", "dd" then [child]
          when "div" then definition_items(child)
          else []
          end
        end
      end

      def embed(node)
        url = @inline.link_url(Image.video_page(node["src"].to_s))
        return [] unless url && @links

        title = Dom.squish(node["title"].to_s)
        [Block.new(:paragraph, title.empty? ? url : "[#{Text.link_text(Text.escape(title))}](#{Text.destination(url)})")]
      end

      def summary(node)
        text = Text.single_line(@inline.render(node.children))
        text.empty? ? [] : [Block.new(:paragraph, "**#{text}**")]
      end

      # Cards that wrap a whole block in one link keep the URL on the headline.
      def linked_blocks(node)
        blocks = children_blocks(node)
        url = @inline.link_url(node["href"].to_s)
        target = url && @links && link_target(blocks)
        return blocks unless target

        if target.kind == :heading
          hashes, text = target.text.split(" ", 2)
          target.text = "#{hashes} [#{Text.link_text(text)}](#{Text.destination(url)})"
        else
          target.text = "[#{Text.link_text(target.text.tr("\n", ' '))}](#{Text.destination(url)})"
        end
        blocks
      end

      def link_target(blocks)
        target = blocks.find { |b| b.kind == :heading } || blocks.find { |b| b.kind == :paragraph && !b.text.start_with?("![") }
        target if target && target.text.length <= 300 && !target.text.include?("](")
      end
    end
  end
end

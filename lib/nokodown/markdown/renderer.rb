# frozen_string_literal: true

module Nokodown
  module Markdown
    # links_home marks a heading that links to the site's root, or sits in
    # such a link, read from the DOM so that links: false, which writes
    # links as text, still tells a logo heading.
    Block = Struct.new(:kind, :text, :level, :links_home)

    # Turns DOM nodes into Markdown blocks. Runs of inline content become
    # paragraphs; block elements are rendered by tag.
    class Renderer
      MAX_DEPTH = 400
      SEPARATOR_LINE = /\A\s*([-=_*~])\1{2,}\s*\z/.freeze
      GLYPHS = "•·▪◦‣►▶▸➤→■●○"
      # A run of glyphs (●●●○○) is a rating, not a bullet.
      BULLET_GLYPH = /\A(?:[#{GLYPHS}](?![#{GLYPHS}])|[-–—](?=\s))\s*/.freeze
      # Any symbols before a space can be an item's marker (+ and - in pros
      # and cons, ✓ and ✗), not only the glyphs that are stripped.
      LEADING_SYMBOLS = /\A[^\p{L}\p{N}\s]+(?=\s)/.freeze

      def initialize(urls, images: true, links: true, redundant_images: {})
        @inline = Inline.new(urls, images: images, links: links, redundant_images: redundant_images)
        @links = links
        @depth = 0
        @contains_block = {}
      end

      def render(nodes)
        nodes.flat_map { |node| block_level?(node) ? block(node) : children_blocks(node) }
      end

      def children_blocks(node)
        blocks = []
        run = []
        node.children.each do |child|
          if block_level?(child)
            blocks.concat(paragraphs(run))
            run = []
            blocks.concat(block(child))
          else
            run << child
          end
        end
        blocks.concat(paragraphs(run))
      end

      def paragraphs(nodes)
        nodes.empty? ? [] : text_paragraphs(@inline.render(nodes))
      end

      # Two or more <br> in a row separate paragraphs, as Readability treats them.
      def text_paragraphs(text)
        text.split(/[ \t]*\n[ \t]*\n\s*/).filter_map do |chunk|
          chunk = Text.tidy(chunk).lines.reject { |line| line.match?(SEPARATOR_LINE) }.join.strip
          Block.new(:paragraph, Text.escape_line_starts(chunk)) unless chunk.empty?
        end
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
        when "pre" then CodeBlock.render(node, CodeBlock.preformatted(node))
        when "code" then CodeBlock.render(node, node.content)
        when "table" then Table.new(self, node).blocks
        when "dl" then definition_list(node)
        when "hr" then [Block.new(:rule, "---")]
        when "iframe" then embed(node)
        when "summary" then summary(node)
        when "a" then linked_blocks(node)
        else children_blocks(node)
        end
      end

      # Text that long is a paragraph some site wrapped in a heading tag.
      def heading(node)
        text = Text.single_line(@inline.render(node.children, heading: true))
        return [] if text.empty?
        return [Block.new(:paragraph, text)] if text.length > 300

        level = node.name[1].to_i
        [Block.new(:heading, "#{'#' * level} #{text}", level, links_home?(node))]
      end

      def links_home?(node)
        node.css("a[href]").any? { |link| Metadata.home_link?(link["href"].strip) }
      end

      def mark_links_home(blocks)
        blocks.each { |block| block.links_home = true if block.kind == :heading }
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
        format_list(items, start)
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
          list_entry(start ? "#{start + index}. " : "- ", blocks, nested_only[index] && !previous && !nested_only[index + 1])
        end
        loose = items.any? { |blocks| blocks.drop(1).any? { |block| block.kind != :list } }
        [Block.new(:list, rendered.join(loose ? "\n\n" : "\n"))]
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

      # A nested list hugs the line above it; other blocks are separated.
      def join_item(blocks)
        blocks.each_with_index.map { |block, index| (index.zero? ? "" : separator(block)) + block.text }.join
      end

      def separator(block)
        block.kind == :list ? "\n" : "\n\n"
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
        return [] if entries.empty?

        runs = entries.slice_when { |a, b| a.include?("\n") || b.include?("\n") }
        [Block.new(:list, runs.map { |run| run.join("\n") }.join("\n\n"))]
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
        mark_links_home(blocks) if Metadata.home_link?(node["href"].to_s.strip)
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

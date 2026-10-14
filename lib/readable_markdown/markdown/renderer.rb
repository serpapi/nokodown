# frozen_string_literal: true

module ReadableMarkdown
  module Markdown
    Block = Struct.new(:kind, :text, :level)

    # Turns DOM nodes into Markdown blocks. Runs of inline content become
    # paragraphs; block elements are rendered by tag.
    class Renderer
      MAX_DEPTH = 400
      SEPARATOR_LINE = /\A\s*([-=_*~])\1{2,}\s*\z/.freeze

      def initialize(urls, images: true, links: true)
        @inline = Inline.new(urls, images: images, links: links)
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
        [Block.new(:heading, "#{'#' * level} #{text}", level)]
      end

      def list(node)
        items = []
        list_children(node).each do |child|
          if child.element? && %w[ul ol].include?(child.name) && items.any?
            items.last.concat(list(child))
          else
            items << list_item(child)
          end
        end
        items.reject!(&:empty?)
        start = node.name == "ol" ? Integer(node["start"].to_s, exception: false) || 1 : nil
        format_list(items, start)
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
        return [] if items.empty?

        rendered = items.each_with_index.map do |blocks, index|
          indent_item(start ? "#{start + index}. " : "- ", join_item(blocks))
        end
        loose = items.any? { |blocks| blocks.drop(1).any? { |block| block.kind != :list } }
        [Block.new(:list, rendered.join(loose ? "\n\n" : "\n"))]
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

      def definition_list(node)
        groups = []
        definition_items(node).each do |item|
          if item.name == "dt"
            term = Text.escape(Dom.text(item))
            groups << [term, []] unless term.empty?
          else
            definition = Text.single_line(children_blocks(item).map(&:text).join(" "))
            next if definition.empty?

            groups << [nil, []] if groups.empty?
            groups.last[1] << definition
          end
        end
        groups.empty? ? [] : [Block.new(:list, groups.map { |term, definitions| definition_line(term, definitions) }.join("\n"))]
      end

      def definition_line(term, definitions)
        return "- #{definitions.join('; ')}" if term.nil?
        return "- **#{term}**" if definitions.empty?

        "- **#{term}**: #{definitions.join('; ')}"
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

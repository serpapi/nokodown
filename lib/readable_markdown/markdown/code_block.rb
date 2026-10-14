# frozen_string_literal: true

module ReadableMarkdown
  module Markdown
    module CodeBlock
      LANGUAGE_CLASS = /\A(?:language|lang|highlight-source|highlight)-([\w+#.-]+)\z/i.freeze
      NO_LANGUAGE = %w[none plain plaintext text nohighlight].freeze

      module_function

      def render(node, raw)
        text = raw.tr(Dom::NBSP, " ").sub(/\A\n/, "").split("\n").map(&:rstrip).join("\n")
        text = text.sub(/\A(?:[ \t]*\n)+/, "").rstrip
        return [] if text.strip.empty?

        fence = Text.code_fence(text)
        [Block.new(:code, "#{fence}#{language(node)}\n#{text}\n#{fence}")]
      end

      # <code> used as a block: <div class="code"><code>multi-line</code></div>.
      def standalone?(node)
        parent = node.parent
        return false if parent.nil? || parent.name == "pre"
        return false unless node.content.strip.include?("\n")

        parent.children.all? { |child| child == node || (child.text? && child.content.strip.empty?) }
      end

      # Highlighters often put each line in its own block element instead of
      # separating lines with "\n".
      def preformatted(node)
        node.children.each_with_object(+"") do |child, out|
          if child.text? || child.cdata?
            out << child.content
          elsif child.name == "br"
            out << "\n"
          elsif Dom.block?(child)
            out << "\n" unless out.empty? || out.end_with?("\n")
            out << preformatted(child)
            out << "\n" unless out.end_with?("\n")
          elsif child.element?
            out << preformatted(child)
          end
        end
      end

      # The language sits on the <pre>, its <code>, or a wrapper up to two
      # levels out (GitHub, Sphinx).
      def language(node)
        [node, node.at_css("code"), node.parent, node.parent&.parent].each do |element|
          next unless element&.element?

          name = explicit_language(element)
          return clean(name) if name
        end
        ""
      end

      def explicit_language(element)
        classes = element["class"].to_s
        element["data-lang"] || element["data-language"] || classes[/brush:\s*([\w+#.-]+)/, 1] ||
          classes.split.map { |name| name[LANGUAGE_CLASS, 1] }.compact.first
      end

      def clean(name)
        name = name.downcase.sub(/\Asource-/, "")
        name.match?(/\A[\w+#.-]{1,24}\z/) && !NO_LANGUAGE.include?(name) ? name : ""
      end
    end
  end
end

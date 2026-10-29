# frozen_string_literal: true

module Nokodown
  module Markdown
    module CodeBlock
      LANGUAGE_CLASS = /\A(?:language|lang|highlight-source|highlight)-([\w+#.-]+)\z/i.freeze
      NO_LANGUAGE = %w[none plain plaintext text nohighlight].freeze
      LANGUAGE_NAMES = Set.new(%w[
        bash sh shell zsh console terminal powershell ps1 cmd batch javascript js jsx typescript ts tsx json yaml yml
        toml xml html css scss sass less python py ruby rb php java kotlin swift go golang rust c c++ cpp csharp c#
        objective-c sql graphql dockerfile makefile r scala perl lua dart elixir haskell clojure groovy gradle ini
        diff markdown md vue svelte nginx http curl text plaintext
      ]).freeze
      # The copy button a highlighter prints with the code.
      COPY = /
        copy(?:\scode|\sto\sclipboard)?|copied!?|copiar(?:\sc[oó]digo)?|copier(?:\sle\scode)?|(?:code\s)?kopieren|
        copia(?:\scodice)?|kopi[eë]ren|копировать(?:\sкод)?|kopiuj(?:\skod)?|kopyala|コピー|コードをコピー|复制(?:代码)?|複製|
        (?:코드\s?)?복사|نسخ(?:\sالكود)?|sao\schép|salin(?:\skode)?
      /xi.freeze
      COPY_LABEL = /\A(?:#{COPY.source})\z/xi.freeze
      COPY_SUFFIX = /\s+(?:#{COPY.source})\z/xi.freeze

      module_function

      # Drops the language label a highlighter prints above the code and its
      # copy button, and fences the code with the labelled language.
      def without_labels(blocks)
        blocks.each_with_index.reject do |block, index|
          label_block?(block, blocks[index + 1], index.positive? && blocks[index - 1])
        end.map(&:first)
      end

      def label_block?(block, following, previous)
        return false unless block.kind == :paragraph
        return previous && previous.kind == :code && block.text.match?(COPY_LABEL) unless following&.kind == :code

        name = block.text.sub(COPY_SUFFIX, "").downcase
        language = LANGUAGE_NAMES.include?(name)
        return false unless block.text.match?(COPY_LABEL) || language || following.text[/\A`+(.*)/, 1] == name

        following.text = following.text.sub(/\A(`+)\n/, "\\1#{name}\n") if language && !NO_LANGUAGE.include?(name)
        true
      end

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

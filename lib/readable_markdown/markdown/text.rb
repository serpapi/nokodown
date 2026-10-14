# frozen_string_literal: true

module ReadableMarkdown
  module Markdown
    # Escaping and whitespace rules. Escapes only what would otherwise change
    # meaning, so prose stays free of backslashes.
    module Text
      INVISIBLE = /[\u00AD\u200B\u2060\uFEFF]/.freeze

      module_function

      def collapse(string)
        string.gsub(INVISIBLE, "").tr(Dom::UNICODE_SPACES, " ").squeeze(" ")
      end

      def escape(string)
        string = string.gsub(/\\(?=[!-\/:-@\[-`{-~])/, "\\\\\\\\")
        string = string.gsub("`", "\\\\`")
        string = string.gsub(/(?<!\s)\*|\*(?!\s)/, "\\\\*")
        string = string.gsub(/(?<![\p{L}\p{N}\\])_|_(?![\p{L}\p{N}])/, "\\\\_")
        string = string.gsub(/\](?=[(\[])/, "\\\\]")
        string.gsub(/<(?=[A-Za-z\/!?])/, "\\\\<")
      end

      # Block syntax that plain text could trigger at the start of a line.
      def escape_line_starts(string)
        string.gsub(/^(#{'#'}{1,6})(?=\s|$)/) { "\\#{Regexp.last_match(1)}" }
              .gsub(/^(>|```|~~~)/) { "\\#{Regexp.last_match(1)}" }
      end

      # Tidy an inline run: no spaces around line breaks, no doubled spaces.
      def tidy(string)
        string.gsub(/[ \t]*\n[ \t]*/, "\n").gsub(/ {2,}/, " ").strip
      end

      def single_line(string)
        tidy(string).gsub(/\s*\n\s*/, " ")
      end

      def code_span(text)
        longest = text.scan(/`+/).map(&:length).max || 0
        fence = "`" * (longest + 1)
        pad = text.start_with?("`") || text.end_with?("`") ? " " : ""
        "#{fence}#{pad}#{text}#{pad}#{fence}"
      end

      def code_fence(text)
        longest = text.scan(/^`{3,}/).map(&:length).max || 0
        "`" * [3, longest + 1].max
      end

      def link_text(text)
        return text if text.count("[") == text.count("]")

        text.gsub(/(?<!\\)([\[\]])/, "\\\\\\1")
      end

      def destination(url)
        url = url.gsub(" ", "%20").gsub("<", "%3C").gsub(">", "%3E")
        url = url.gsub("(", "%28").gsub(")", "%29") unless url.count("(") == url.count(")")
        url
      end

      # Markdown back to readable text: no images, link targets, emphasis or
      # escapes.
      def plain(markdown)
        markdown.gsub(/!\[[^\]]*\]\([^)]*\)/, "")
                .gsub(/\[([^\]]*)\]\([^)]*\)/, '\1')
                .gsub(/\\([\\`*_\[\]<>#|])/, '\1')
                .gsub(/\*\*|\*|~~|`/, "")
                .strip
      end

      def table_cell(text)
        single_line(text).gsub(/(?<!\\)\|/, "\\|")
      end
    end
  end
end

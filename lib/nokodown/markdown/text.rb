# frozen_string_literal: true

module Nokodown
  module Markdown
    # Escaping and whitespace rules. Escapes only what would otherwise change
    # meaning, so prose stays free of backslashes.
    module Text
      INVISIBLE = "\u00AD\u200B\u2060\uFEFF"
      # Every character escape may change; most text has none.
      ESCAPABLE = /[\\`*_\]<]/.freeze
      # What CommonMark reads as an entity reference.
      ENTITY = /&(?=(?:[A-Za-z][A-Za-z0-9]{1,31}|#\d{1,7}|#[xX]\h{1,6});)/.freeze
      SCHEME = /\A[A-Za-z][A-Za-z0-9+.-]*:/.freeze

      module_function

      def collapse(string)
        string = string.delete(INVISIBLE) unless string.ascii_only?
        Dom.spaces_to_blanks(string).squeeze(" ")
      end

      def escape(string)
        return string unless string.match?(ESCAPABLE)

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

      # Text not escaped yet, as link text with every bracket escaped, so no
      # input can end the label early. A backslash that escapes a character
      # keeps it; one at the end would escape the "]".
      def label(text)
        escape(text).gsub(/\\.|\\\z|[\[\]]/m) { |match| match.length == 2 ? match : "\\#{match}" }
      end

      # Markdown decodes backslash escapes and entity references in a
      # destination, so "javascript\\:" or "javascript&colon;" would read as a
      # script link. Backslashes are percent-encoded, and so is an entity
      # that comes before the path of a URL without a scheme, where it could
      # spell one.
      def destination(url)
        url = url.gsub(" ", "%20").gsub("<", "%3C").gsub(">", "%3E").gsub("\\", "%5C")
        url = encode_scheme_entities(url) if url.include?("&") && !url.match?(SCHEME)
        url = url.gsub("(", "%28").gsub(")", "%29") unless url.count("(") == url.count(")")
        url
      end

      def encode_scheme_entities(url)
        path = url.index(%r{[/?]}) || url.length
        url.gsub(ENTITY) { Regexp.last_match.begin(0) < path ? "%26" : "&" }
      end

      # Markdown back to readable text: no images, link targets, emphasis or
      # escapes.
      def plain(markdown)
        unlink(markdown).gsub(/\\([\\`*_\[\]<>#|])/, '\1').gsub(/\*\*|\*|~~|`/, "").strip
      end

      # Markdown without images and link targets; link text stays.
      def unlink(markdown)
        markdown.gsub(/!\[[^\]]*\]\([^)]*\)/, "").gsub(/\[([^\]]*)\]\([^)]*\)/, '\1')
      end

      def table_cell(text)
        single_line(text).gsub(/(?<!\\)\|/, "\\|")
      end
    end
  end
end

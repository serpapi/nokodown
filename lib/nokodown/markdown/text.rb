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
      DESTINATION_UNSAFE = /[\x00-\x20\x7F<>\\]/.freeze
      # How deep CommonMark (cmark, markdown-it) nests parentheses in a
      # destination before it stops reading it as one.
      MAX_PARENTHESES = 32

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

      # Escaped text as link text, so that it ends at the "]" written after
      # it. Brackets stay only where they pair in order; otherwise each one
      # not escaped is. A backslash left at the end, which would escape that
      # "]", is escaped too.
      def link_text(text)
        return text unless text.match?(/[\[\]\\]/)

        paired = paired_brackets?(text)
        text.gsub(/\\.|\\\z|[\[\]]/m) do |match|
          match.length == 2 || (paired && match != "\\") ? match : "\\#{match}"
        end
      end

      def paired_brackets?(text)
        depth = 0
        text.scan(/\\.|[\[\]]/m) do |match|
          next if match.length == 2

          depth += match == "[" ? 1 : -1
          return false if depth.negative?
        end
        depth.zero?
      end

      # Text not escaped yet, as link text with every bracket escaped, so no
      # input can end the label early. A backslash that escapes a character
      # keeps it; one at the end would escape the "]".
      def label(text)
        escape(text).gsub(/\\.|\\\z|[\[\]]/m) { |match| match.length == 2 ? match : "\\#{match}" }
      end

      # A destination is written so that it is read whole and as it is.
      # Spaces and control characters would end it and "<" open another
      # form of it. Markdown decodes backslash escapes and entity references
      # in it, so "javascript\\:" or "javascript&colon;" would read as a
      # script link: backslashes are percent-encoded, and so is an entity
      # that comes before the path of a URL without a scheme, where it could
      # spell one. Parentheses stay only where Markdown pairs them, or a
      # ")" would end the destination early and let the rest of the URL
      # write a link of its own.
      def destination(url)
        url = url.gsub(DESTINATION_UNSAFE) { |char| format("%%%02X", char.ord) }
        url = encode_scheme_entities(url) if url.include?("&") && !url.match?(SCHEME)
        url = url.gsub("(", "%28").gsub(")", "%29") unless paired_parentheses?(url)
        url
      end

      # Every ")" closes an earlier "(", at most MAX_PARENTHESES deep.
      def paired_parentheses?(url)
        depth = 0
        url.scan(/[()]/) do |paren|
          depth += paren == "(" ? 1 : -1
          return false if depth.negative? || depth > MAX_PARENTHESES
        end
        depth.zero?
      end

      # Only the part before the path can spell a scheme. An entity cannot
      # reach past the first "/" or "?", so that part is encoded on its own,
      # without asking each match where it is (slow in a long non-ASCII URL).
      def encode_scheme_entities(url)
        path = url.index(%r{[/?]}) || url.length
        "#{url[0, path].gsub(ENTITY, '%26')}#{url[path..-1]}"
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

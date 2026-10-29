# frozen_string_literal: true

module Nokodown
  module Markdown
    # Escaping and whitespace rules. Escapes only what would otherwise change
    # meaning, so prose stays free of backslashes.
    module Text
      # Joiners count only between letters or emoji (Persian words, family
      # emoji); private-use characters are icon-font glyphs.
      INVISIBLE = /
        [\u00AD\u200B\u2060\uFEFF\p{Co}]|
        (?<![\p{L}\p{M}\p{So}\p{Sk}])[\u200C\u200D]|[\u200C\u200D](?![\p{L}\p{M}\p{So}\p{Sk}])
      /x.freeze
      # Characters that could open or close emphasis. An underscore inside a
      # word cannot.
      DELIMITERS = { "*" => /\*/, "_" => /(?<![\p{L}\p{N}\p{M}])_|_(?![\p{L}\p{N}\p{M}])/ }.freeze
      ESCAPED_RUNS = { "*" => /(?:\\\*)+/, "_" => /(?:\\_)+/ }.freeze
      # A text holds one run, so a run that opens a line is that run.
      LINE_START_RUNS = { "*" => /^(?:\\\*)+(?:\s|$)/, "_" => /^(?:\\_)+(?:\s|$)/ }.freeze
      # Link and image markup as Inline writes it: "](" in the text is escaped,
      # and the destination's parentheses are balanced or percent-encoded.
      LINK_TEXT = /(?:\\.|[^\\\[\]\n]|\[(?:\\.|[^\\\[\]\n])*\])*/.freeze
      DESTINATION = /(?:[^()\s]|\([^()\s]*\))*/.freeze
      LEADING_IMAGES = /\A(?:!\[#{LINK_TEXT}\]\(#{DESTINATION}\)\s*)+/.freeze
      ENCODED_NON_ASCII = /(?:%[89A-F]\h)+/i.freeze
      # Spaces and invisible characters would end or hide the destination.
      UNPRINTABLE = /[\p{Z}\p{C}]/.freeze

      module_function

      def collapse(string)
        string.gsub(INVISIBLE, "").tr(Dom::UNICODE_SPACES, " ").squeeze(" ")
      end

      def escape(string)
        string = string.gsub(/\\(?=[!-\/:-@\[-`{-~])/, "\\\\\\\\")
        string = string.gsub("`", "\\\\`")
        string = string.gsub(/(?<!\s)\*|\*(?!\s)/, "\\\\*")
        string = string.gsub(/(?<![\p{L}\p{N}\p{M}\\])_|_(?![\p{L}\p{N}\p{M}])/, "\\\\_")
        string = string.gsub(/\](?=[(\[])/, "\\\\]")
        string.gsub(/<(?=[A-Za-z\/!?])/, "\\\\<")
      end

      # An escaped asterisk or underscore needs its backslash only when another
      # one in the paragraph could pair with it, or when it would start a list
      # item. A lone run cannot pair: "2011*", "Leser*innen", "!_Tokyo". Image
      # markup stays as written, since Cleanup finds images by it.
      def unescape_lone(string)
        return string if string.include?("![")

        DELIMITERS.reduce(string) do |text, (char, delimiter)|
          runs = text.scan(ESCAPED_RUNS[char])
          next text unless runs.size == 1 && text.scan(delimiter).size == runs.first.length / 2

          run = runs.first
          text.match?(LINE_START_RUNS[char]) ? text : text.sub(run, char * (run.length / 2))
        end
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
        url.gsub(ENCODED_NON_ASCII) { |run| readable(run) }
      end

      # A word in another script costs a token or two as letters and two or
      # three per letter percent-encoded. The URL means the same either way
      # (RFC 3987).
      def readable(run)
        decoded = [run.delete("%")].pack("H*").force_encoding(Encoding::UTF_8)
        return run unless decoded.valid_encoding?

        decoded.gsub(UNPRINTABLE) { |char| char.bytes.map { |byte| format("%%%02X", byte) }.join }
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

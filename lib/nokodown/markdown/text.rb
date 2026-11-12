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
      DESTINATION_UNSAFE = /[\x00-\x20\x7F<>\\\[\]`]/.freeze
      # An IPv6 host keeps its brackets: scheme, user info, host.
      IPV6_HOST = %r{\A([A-Za-z][A-Za-z0-9+.-]*://)([^/?#\[\]]*@)?(\[[\h:.]+\])(?=[:/?#]|\z)}.freeze
      # How deep CommonMark (cmark, markdown-it) nests parentheses in a
      # destination before it stops reading it as one.
      MAX_PARENTHESES = 32
      # Link text in pieces: backticks, a backslash, a bracket, a "<" or
      # anything else.
      LINK_TEXT_TOKEN = /`+|\\|[\[\]<]|[^\\`\[\]<]+/.freeze
      # The longest backtick run that CommonMarker (cmark-gfm) reads as the
      # fence of a code span; a longer one is text.
      MAX_BACKTICKS = 80
      # What can follow the "<" of an autolink or an HTML tag: a letter
      # (scheme or tag name), "/", "!" or "?", or the local part of an email
      # address and its "@".
      EMAIL_LOCAL = "A-Za-z0-9.!\\#$%&'*+/=?^_`{|}~-"
      AUTOLINK_START = %r{[A-Za-z/!?]|[#{EMAIL_LOCAL}]+@}.freeze
      AUTOLINK = /<(?=#{AUTOLINK_START.source})/.freeze
      AUTOLINK_AFTER = /\A(?:#{AUTOLINK_START.source})/.freeze
      EMAIL_PART = /\A[#{EMAIL_LOCAL}]+\z/.freeze
      EMAIL_END = /\A[#{EMAIL_LOCAL}]*@/.freeze
      # Markdown syntax in raw TeX, after the backslashes that do not escape
      # it (an even run).
      TEX_SYNTAX = /(?<!\\)((?:\\\\)*+)(`|<(?=#{AUTOLINK_START.source})|\](?=[(\[]))/.freeze

      module_function

      def collapse(string)
        string = string.delete(INVISIBLE) unless string.ascii_only?
        Dom.spaces_to_blanks(string).squeeze(" ")
      end

      def escape(string)
        return string unless string.match?(ESCAPABLE)

        string = string.gsub(/\\(?=[!-\/:-@\[-`{-~]|\z)/, "\\\\\\\\")
        string = string.gsub("`", "\\\\`")
        string = string.gsub(/(?<!\s)\*|\*(?!\s)/, "\\\\*")
        string = string.gsub(/(?<![\p{L}\p{N}\\])_|_(?![\p{L}\p{N}])/, "\\\\_")
        string = string.gsub(/\](?=[(\[])/, "\\\\]")
        string.gsub(AUTOLINK, "\\\\<")
      end

      # Raw TeX keeps its backslashes and braces, so "\\frac" or "\\{" reach a
      # math renderer as written, but nothing in it may start Markdown that
      # reaches past it: a backtick, a "<" that would open an autolink or an
      # HTML tag, or a "]" before "(" or "[" gets a backslash unless one
      # escapes it already. Line breaks become spaces, so no line of it
      # starts a block.
      def tex(tex)
        collapse(tex).strip.gsub(TEX_SYNTAX, "\\1\\\\\\2")
      end

      # Block syntax that plain text could trigger at the start of a line.
      # Three backticks open a code block only if no backtick follows on the
      # line; then each is escaped, so none is left to pair with a run on a
      # later line. Otherwise they open a code span and stay.
      def escape_line_starts(string)
        string.gsub(/^(#{'#'}{1,6})(?=\s|$)/) { "\\#{Regexp.last_match(1)}" }
              .gsub(/^(>|~~~)/) { "\\#{Regexp.last_match(1)}" }
              .gsub(/^`{3,}(?=[^`\n]*$)/) { |run| "\\`" * run.length }
      end

      # Tidy an inline run: no spaces around line breaks, no doubled spaces.
      def tidy(string)
        string.gsub(/[ \t]*\n[ \t]*/, "\n").gsub(/ {2,}/, " ").strip
      end

      def single_line(string)
        tidy(string).gsub(/\s*\n\s*/, " ")
      end

      # Code with a backtick run too long to fence is written as text.
      def code_span(text)
        longest = text.scan(/`+/).map(&:length).max || 0
        return escape(text) if longest >= MAX_BACKTICKS

        fence = "`" * (longest + 1)
        pad = text.start_with?("`") || text.end_with?("`") ? " " : ""
        "#{fence}#{pad}#{text}#{pad}#{fence}"
      end

      def code_fence(text)
        longest = text.scan(/^`{3,}/).map(&:length).max || 0
        "`" * [3, longest + 1].max
      end

      # Escaped text as link text, so that it ends at the "]" written after
      # it. It is read as Markdown reads it: a code span is literal, so its
      # brackets and backslashes stay as they are. Outside code spans, a "]"
      # before "(" or "[" is escaped, and so is a "<" that would open an
      # autolink or an HTML tag, so the text holds no link or tag of its own
      # (raw TeX can), and brackets stay only where they pair in order;
      # otherwise each one not escaped is. Backticks that open no code span
      # within the text are escaped, so none can pair with one around the
      # link, and so is a backslash left at the end, which would escape
      # that "]".
      def link_text(text)
        return text unless text.match?(/[\[\]\\`<]/)

        tokens = text.scan(LINK_TEXT_TOKEN)
        runs = backtick_runs(tokens)
        pieces = []
        brackets = []
        index = 0
        while index < tokens.length
          token = tokens[index]
          if token == "\\"
            index = escape_in_link_text(tokens, index, runs, pieces)
          elsif token.start_with?("`")
            index = code_span_in_link_text(tokens, index, token.length, runs, pieces)
          elsif token == "]" && tokens[index + 1]&.start_with?("(", "[")
            pieces << "\\]"
            index += 1
          elsif token == "<" && autolink_start?(tokens, index + 1)
            pieces << "\\<"
            index += 1
          else
            brackets << pieces.length if token == "[" || token == "]"
            pieces << token
            index += 1
          end
        end
        brackets.each { |at| pieces[at] = "\\#{pieces[at]}" } unless paired_brackets?(brackets.map { |at| pieces[at] })
        pieces.join
      end

      # Whether the tokens from `index` on continue a "<" into an autolink
      # or an HTML tag. An email address can hold backticks, so its local
      # part may run over several tokens; it ends at the first token that
      # is not part of it, so no token is read twice.
      def autolink_start?(tokens, index)
        token = tokens[index]
        return false unless token
        return true if token.match?(%r{\A[A-Za-z/!?]})

        while token
          return true if token.match?(EMAIL_END)
          return false unless token.match?(EMAIL_PART)

          index += 1
          token = tokens[index]
        end
        false
      end

      # Token indexes of the backtick runs of each length, in order.
      def backtick_runs(tokens)
        runs = Hash.new { |hash, length| hash[length] = [] }
        tokens.each_with_index { |token, index| runs[token.length] << index if token.start_with?("`") }
        runs
      end

      # A backslash escapes what follows it, or the "]" after the text if
      # nothing does. An escaped backtick leaves the rest of its run, which
      # can open a code span.
      def escape_in_link_text(tokens, index, runs, pieces)
        following = tokens[index + 1]
        if following.nil?
          pieces << "\\\\"
          index + 1
        elsif following.start_with?("`")
          pieces << "\\`"
          return index + 2 if following.length == 1

          code_span_in_link_text(tokens, index + 1, following.length - 1, runs, pieces)
        elsif following == "\\" || following == "[" || following == "]" || following == "<"
          pieces << "\\#{following}"
          index + 2
        else
          pieces << "\\"
          index + 1
        end
      end

      # The last `length` backticks of the run at `index` open a code span
      # if a later run is as long and neither is too long to be a fence;
      # inside it, nothing is escaped. Otherwise they are escaped one by one.
      def code_span_in_link_text(tokens, index, length, runs, pieces)
        closer = runs[length].bsearch { |at| at > index } if length <= MAX_BACKTICKS
        unless closer
          pieces << ("\\`" * length)
          return index + 1
        end

        pieces << ("`" * length) << tokens[(index + 1)..closer].join
        closer + 1
      end

      # Every "]" closes an earlier "[".
      def paired_brackets?(brackets)
        depth = 0
        brackets.each do |bracket|
          depth += bracket == "[" ? 1 : -1
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
      # write a link of its own. Brackets and backticks are percent-encoded
      # too: if text around the link keeps Markdown from reading it as one
      # (a backslash or a backtick before it), the URL is read as text, and
      # must not hold a link or a code span of its own.
      def destination(url)
        url = encode_unsafe(url)
        url = encode_scheme_entities(url) if url.include?("&") && !url.match?(SCHEME)
        url = url.gsub("(", "%28").gsub(")", "%29") unless paired_parentheses?(url)
        url
      end

      # Everything but the brackets of an IPv6 host, user info included.
      def encode_unsafe(url)
        host = url.match(IPV6_HOST)
        return percent_encode(url) unless host

        "#{host[1]}#{percent_encode(host[2].to_s)}#{host[3]}#{percent_encode(host.post_match)}"
      end

      def percent_encode(string)
        string.gsub(DESTINATION_UNSAFE) { |char| format("%%%02X", char.ord) }
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
        single_line(text).gsub("|", "\\|")
      end
    end
  end
end

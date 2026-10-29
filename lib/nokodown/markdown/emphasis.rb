# frozen_string_literal: true

module Nokodown
  module Markdown
    # Emphasis that carries no meaning: runs a page split in two, and runs
    # around a whole paragraph, cell, heading or link text. Text escapes
    # literal asterisks, so every unescaped one here is a marker.
    module Emphasis
      # A bold run closing right where the next opens, as in "**a****b**" or
      # "**a** **b**". An italic pair needs the space: "a**b" is a bold run
      # closing before a word.
      ADJACENT_BOLD = /(?<=[^\s*\\])\*\*( ?)\*\*(?=[^\s*])/.freeze
      ADJACENT_ITALIC = /(?<=[^\s*\\])\* \*(?=[^\s*])/.freeze
      OPENING = /\A\*{1,3}(?=[^\s*])/.freeze
      CLOSING = /(?<=[^\s*\\])\*{1,3}\z/.freeze
      MARKER = /(?<!\\)\*+/.freeze
      LABEL_LENGTH = 60
      LABEL_WORDS = 8
      SENTENCE_END = /[.!?…;,。！？；，]\z/.freeze

      module_function

      def merge(text)
        text.gsub(ADJACENT_BOLD, '\1').gsub(ADJACENT_ITALIC, " ")
      end

      # Text without the emphasis runs that wrap all of it.
      def unwrap(text)
        loop do
          inner = whole_run(text)
          return text unless inner

          text = inner
        end
      end

      # A paragraph keeps a bold run around a short label, which stands in
      # for a heading ("**Ingredients**"); sentences and italics lose theirs.
      def paragraph(text)
        text = merge(text)
        inner = unwrap(text)
        return text if inner == text

        bold?(text) && label?(inner) ? "**#{inner}**" : inner
      end

      def label?(text)
        plain = Text.plain(text)
        !plain.include?("\n") && plain.length <= LABEL_LENGTH && plain.split.size <= LABEL_WORDS && !plain.match?(SENTENCE_END)
      end

      def bold?(text)
        opening = text[OPENING].to_s.length
        closing = text[CLOSING].to_s.length
        opening >= 2 && closing >= 2
      end

      # The text inside the run that wraps the whole text, or nil. "***Note:**
      # x*" is an italic run around a bold one; "**a** and **b**" opens and
      # closes with markers but holds two runs.
      def whole_run(text)
        size = [text[OPENING].to_s.length, text[CLOSING].to_s.length].min
        return if size.zero?

        inner = text[size...-size]
        inner unless inner.scan(MARKER).any? { |marker| same_kind?(marker.length, size) }
      end

      def same_kind?(marker, run)
        run == 3 || marker == run || marker >= 3
      end
    end
  end
end

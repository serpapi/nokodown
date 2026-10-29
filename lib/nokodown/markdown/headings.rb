# frozen_string_literal: true

module Nokodown
  module Markdown
    # What a heading tag holds that is not a heading: emoji, arrows and
    # separators set before or after its text ("📱 Benefits", "☛ Taxi",
    # "- Forum"), and text that names no section, such as a date, a price
    # or a sentence a site set large.
    module Headings
      STAR = "[★☆⭐✩✪✫✬✭✮✯]"
      # A sign before a number, a lowercase word or a bracket belongs to it
      # ("+ de 300 modèles", "- (subtraction)"). A dash before the text marks
      # a quote in Nordic news ("– Problemene er løst"), unless another
      # closes the text as a frame ("— Blog —").
      SIGN = "[-+](?!\\s+[\\p{Ll}\\p{N}(\\[])"
      DECORATION = "#{Text::PICTOGRAPH}|[|·•;,/~=]"
      # Two stars or more are a rating.
      LEADING = /\A(?:(?!#{STAR}\uFE0F?#{STAR})(?:#{DECORATION}|[:»›]|#{SIGN}|\\[*_])+\s+)+/.freeze
      # Matched on the reversed text. A colon stays, as French sets one apart,
      # and so does a closing guillemet when an opening one pairs with it.
      TRAILING = /\A(?:(?!\uFE0F?#{STAR}\uFE0F?#{STAR})(?:#{DECORATION}|[-–—+]|[*_]\\)+\s+)+/.freeze
      UNQUOTED_TRAILING = /\A(?:(?!\uFE0F?#{STAR}\uFE0F?#{STAR})(?:#{DECORATION}|[-–—+»›]|[*_]\\)+\s+)+/.freeze
      OPENING_DASH = /\A[–—]\s+/.freeze
      OPENING_GUILLEMET = /[«‹]/.freeze
      CONTENT = /[\p{L}\p{N}]|#{STAR}\uFE0F?#{STAR}/.freeze
      SENTENCE_END = /(?<![.…])[.!。]\z/.freeze
      # Taglines a landing page sets over its sections are shorter.
      SENTENCE_WORDS = 16
      # Scripts written without spaces between words.
      SENTENCE_CHARACTERS = 50
      UNSPACED = /[\p{Han}\p{Hiragana}\p{Katakana}\p{Thai}]/.freeze
      # A year names a period, and a counter numbers the section below it.
      NUMBERING = /\A(?:\d{4}(?:\s?[-–\/]\s?\d{2,4})?|\d{1,3}[.)]?)\z/.freeze
      LINK = /\A\[#{Text::LINK_TEXT}\]\(#{Text::DESTINATION}\)\z/.freeze

      module_function

      def undecorated(text)
        text = text.sub(OPENING_DASH, "") if text.end_with?(" –", " —")
        text = text.sub(LEADING, "")
        Separators.trim_end(text, text.match?(OPENING_GUILLEMET) ? TRAILING : UNQUOTED_TRAILING)
      end

      # Letters, digits or a rating; other signs only decorate.
      def content?(text)
        Text.plain(text).match?(CONTENT)
      end

      # A page's headline may be anything; below it, text without letters (a
      # date, a price, a phone number, but not a year or a counter) is a
      # paragraph, and so is a sentence, unless it is a card's title, which
      # names another page. Runs last: until then such a heading still ends
      # a section, so the boilerplate a site sets in heading tags at the end
      # of a page goes with the other empty sections, and a number under it
      # is that heading's value, not a counter.
      def paragraphs(blocks)
        blocks.map do |block|
          next block unless block.kind == :heading && block.level > 1

          text = block.content
          paragraph?(text) ? Block.new(:paragraph, Text.escape_line_starts(text)) : block
        end
      end

      def paragraph?(text)
        plain = Text.plain(text)
        return !plain.match?(NUMBERING) unless plain.match?(/\p{L}/)

        !text.match?(LINK) && sentence?(plain)
      end

      def sentence?(plain)
        return false unless plain.match?(SENTENCE_END)

        plain.split.size >= SENTENCE_WORDS || (plain.match?(UNSPACED) && plain.length >= SENTENCE_CHARACTERS)
      end
    end
  end
end

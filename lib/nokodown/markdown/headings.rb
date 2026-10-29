# frozen_string_literal: true

module Nokodown
  module Markdown
    # What a heading tag holds that is not a heading: emoji, arrows and
    # separators set before or after its text ("📱 Benefits", "☛ Taxi",
    # "- Forum"), and text that names no section, such as a date, a price
    # or a sentence a site set large.
    module Headings
      # Pictographs, dingbats, arrows and shapes, but not the signs that are
      # part of a name or a value (©, №, °, ℃).
      SYMBOL = "[\\p{So}\u2190-\u21FF\u25B7\u25C1\u27F0-\u27FF\u2900-\u297F\uFE0F\u200D&&[^\u00A9\u00AE\u2122\u2120\u2117\u00B0\u2100-\u214F]]"
      SEPARATOR = "[-–—|·•:;,/+»›~=]|\\\\[*_]"
      LEADING = /\A(?:(?:#{SYMBOL}|#{SEPARATOR})+\s+)+/.freeze
      # Matched on the reversed text: Ruby would retry a pattern anchored at
      # the end from every start. A colon stays, as French sets one apart.
      TRAILING = /\A(?:(?:#{SYMBOL}|[-–—|·•;,\/+»›~=]|[*_]\\)+\s+)+/.freeze
      SENTENCE_END = /(?<![.…])[.!。！]\z/.freeze
      # Taglines a landing page sets over its sections are shorter.
      SENTENCE_WORDS = 16
      # Scripts written without spaces between words.
      SENTENCE_CHARACTERS = 50
      UNSPACED = /[\p{Han}\p{Hiragana}\p{Katakana}\p{Thai}]/.freeze
      YEARS = /\A\d{4}(?:\s?[-–\/]\s?\d{2,4})?\z/.freeze
      LINK = /\A\[[^\n]*\]\([^()\s]*\)\z/.freeze

      module_function

      def undecorated(text)
        text = text.sub(LEADING, "")
        tail = text.reverse[TRAILING]
        tail ? text.delete_suffix(tail.reverse) : text
      end

      # A page's headline may be anything; below it, text without letters (a
      # date, a price, a phone number, but not a year, which names a period)
      # is a paragraph, and so is a sentence, unless it is a card's title,
      # which names another page.
      def paragraph?(text, level, linked: false)
        return false if level == 1

        plain = Text.plain(text)
        return !plain.match?(YEARS) unless plain.match?(/\p{L}/)

        !linked && !text.match?(LINK) && sentence?(plain)
      end

      def sentence?(plain)
        return false unless plain.match?(SENTENCE_END)

        plain.split.size >= SENTENCE_WORDS || (plain.match?(UNSPACED) && plain.length >= SENTENCE_CHARACTERS)
      end
    end
  end
end

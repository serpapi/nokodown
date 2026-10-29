# frozen_string_literal: true

require "set"
require "uri"

module Nokodown
  # The words of the last segment of a page's URL ("/blog/401k-to-roth-ira-
  # rollover/"), which name the page as its author did when publishing it.
  # Ids and short slugs say too little to compare names with.
  class UrlWords
    EXTENSION = /\.(?:s?html?|php\d?|aspx?|jsp|cgi)\z/i.freeze
    WORD = /[\p{L}\p{N}]+/.freeze
    MIN_WORDS = 3
    MIN_NAMES = 2
    COVERAGE = 0.6
    SAME_NAME = 0.8
    MARGIN = 0.25

    def initialize(url)
      segment = url.to_s[SiteName::URL, 2].to_s.split("/").reject(&:empty?).last.to_s.sub(EXTENSION, "")
      words = fold(decode(segment)).scan(WORD)
      @words = words.size >= MIN_WORDS && words.count { |word| word.match?(/\p{L}{3}/) } >= MIN_NAMES ? words : []
    end

    def names?(text)
      coverage(text) >= COVERAGE
    end

    # Whether the text is the URL's name: it has nearly all of the URL's
    # words, and they make most of it. "Digital Marketing Strategy" at
    # "/what-is-digital-marketing/" is another topic that uses its words.
    def same_name?(text)
      words = fold(text).scan(WORD)
      own = @words.to_set
      shared = words.sum { |word| own.include?(word) ? word.length : 0 }
      coverage(text) >= SAME_NAME && shared >= words.sum(&:length) * COVERAGE
    end

    # Whether the URL names the text, and clearly more than the other one.
    def prefers?(text, other)
      coverage = coverage(text)
      coverage >= COVERAGE && coverage >= coverage(other) + MARGIN
    end

    # The share of the URL's letters that the text's words cover.
    def coverage(text)
      return 0.0 if @words.empty?

      words = fold(text).scan(WORD).to_set
      @words.sum { |word| words.include?(word) ? word.length : 0 }.fdiv(@words.sum(&:length))
    end

    private

    def decode(segment)
      URI.decode_www_form_component(segment).scrub("")
    rescue ArgumentError
      segment
    end

    def fold(text)
      text.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase
    end
  end
end

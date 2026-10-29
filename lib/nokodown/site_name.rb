# frozen_string_literal: true

module Nokodown
  # The site's own name, as it declares it, as its domain spells it and as
  # its logo heading shows it, so titles and headings that only name the
  # site can be told from the page's own name.
  class SiteName
    # An underscore separates only where it touches a space or a non-ASCII
    # letter ("标题_栏目_网站"); between ASCII letters it joins a file name.
    PART_SEPARATOR = %r{\s+[|\-–—»>→/\\·•]+\s+|\s*\|\s*|\s_\s?|_\s|(?<=[^\x00-\x7F])_|_(?=[^\x00-\x7F])}.freeze
    BREADCRUMB = /[»>→\\]/.freeze
    URL = %r{\A[a-z][a-z\d+.-]*://(?:[^@/?#]*@)?([^/:?#]+)(?::\d+)?([^?#]*)}i.freeze
    HOME_PATH = %r{\A/?(?:index\.[a-z]+|[a-z]{2}(?:[-_][a-z]{2})?/?)?\z}i.freeze
    # Labels under a country code that are not the site's name (example.co.uk).
    SECOND_LEVEL = %w[ac co com edu go gob gouv gov ne net nic or org].freeze
    WORD = /[\p{L}\p{N}]+/.freeze
    CAPITAL = /\p{Lu}/.freeze
    MIN_PREFIX = 3
    MIN_BRAND = 4
    MAX_DOMAIN_WORDS = 3

    def initialize(url, names)
      host, path = url.to_s.match(URL)&.captures
      @home = host && path.match?(HOME_PATH)
      @domains = domain_keys(host.to_s.downcase)
      @names = names.compact.map { |name| key(name) }.reject(&:empty?)
    end

    # The site's name or its domain.
    def name?(text)
      key = key(text)
      !key.empty? && (@domains.include?(key) || @names.include?(key))
    end

    def home?
      @home
    end

    # Drops the parts of a title that name the site from either end. On the
    # site's home page the site is the page, so nothing is dropped. After a
    # site name that leads a breadcrumb ("Site » Section » Page - Part 2"),
    # the page starts after the breadcrumb's last separator.
    def without(title)
      separators = title.to_enum(:scan, PART_SEPARATOR).map { Regexp.last_match }
      return title if @home || separators.empty?

      bounds = [0] + separators.flat_map { |separator| [separator.begin(0), separator.end(0)] } + [title.length]
      parts = bounds.each_slice(2).map { |from, to| title[from...to] }
      last = (tail_start(title, bounds, parts.size) || parts.size) - 1
      first = 0
      first += 1 while first < last && name?(parts[first])
      first += last_crumb(separators[(first - 1)...last]) if first.positive?
      kept = title[bounds[2 * first]...bounds[2 * last + 1]]
      kept.strip.empty? ? title : kept
    end

    # What follows the page's name in a title: the site's name, the start of
    # a declared name that goes on with a slogan, or a slogan that mentions
    # the domain ("Find great deals on trivago").
    def ending?(text)
      site_tail?(text) || mentions_domain?(text)
    end

    private

    def last_crumb(separators)
      separators.rindex { |separator| separator[0].match?(BREADCRUMB) } || 0
    end

    # The longest end that names the site, or else the shortest that
    # mentions its domain: "iPhone 15 | Shop | Apple" keeps "iPhone 15 |
    # Shop", not just what comes before the first mention.
    def tail_start(title, bounds, count)
      tails = (1...count).map { |index| [index, title[bounds[2 * index]..]] }
      tails.find { |_, tail| site_tail?(tail) }&.first || tails.reverse.find { |_, tail| mentions_domain?(tail) }&.first
    end

    # A declared name may go on with a slogan the title leaves out ("Giełda
    # odpadów" for "Giełda odpadów → Dziennik Gospodarki").
    def site_tail?(text)
      key = key(text)
      !key.empty? && (name?(text) || (key.length >= MIN_PREFIX && @names.any? { |name| name.start_with?(key) }))
    end

    # A label of a few letters alone is most often a word of the title
    # ("in" for in.gov, "nu" for nu.nl), unless the title writes it with
    # capitals after its first letter, as it does acronyms ("AXA", "iA").
    def mentions_domain?(text)
      words = text.scan(WORD)
      brand, spelled = @domains
      words.each_index.any? do |start|
        (1..MAX_DOMAIN_WORDS).any? do |count|
          key = key(words[start, count].join)
          key == spelled || (key == brand && (count > 1 || brand_word?(words[start])))
        end
      end
    end

    def brand_word?(word)
      word.length >= MIN_BRAND || word[1..].match?(CAPITAL)
    end

    # The label before the public suffix names the site; with the suffix it
    # is how a title spells the domain ("GTA-Series.com", "Edisonline SK").
    def domain_keys(host)
      labels = host.sub(/\Awww\d*\./, "").split(".")
      return [] if labels.size < 2 || labels.last.match?(/\A\d+\z/)

      suffix = [labels.pop]
      suffix.unshift(labels.pop) if labels.size > 1 && SECOND_LEVEL.include?(labels.last)
      brand = key(labels.last)
      [brand, brand + suffix.join]
    end

    def key(text)
      text.to_s.downcase.scan(WORD).join
    end
  end
end

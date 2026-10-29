# frozen_string_literal: true

module Nokodown
  # The site's own name, as it declares it, as its domain spells it and as
  # its logo heading shows it, so titles and headings that only name the
  # site can be told from the page's own name.
  class SiteName
    # An underscore separates only where it touches a space or a non-ASCII
    # letter ("标题_栏目_网站"); between ASCII letters it joins a file name.
    UNDERSCORE = '\s_\s?|_\s|(?<=[^\x00-\x7F])_|_(?=[^\x00-\x7F])'
    PART_SEPARATOR = %r{\s+[|\-–—»>→/\\·•]+\s+|\s*\|\s*|#{UNDERSCORE}}.freeze
    BREADCRUMB = /[»>→\\]/.freeze
    URL = %r{\A[a-z][a-z\d+.-]*://(?:[^@/?#]*@)?([^/:?#]+)(?::\d+)?([^?#]*)}i.freeze
    # The site's root, its index page, or a language's root ("/it/", "/en-us").
    ROOT_PATH = '/?(?:index\.[a-z]+|[a-z]{2}(?:[-_][a-z]{2})?/?)?'
    HOME_PATH = /\A#{ROOT_PATH}\z/i.freeze
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
      last = (tail_start(parts) || parts.size) - 1
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
    # Shop", not just what comes before the first mention. The page sets
    # its title, however long, so no end is read twice: separators hold no
    # word characters, so an end's key is its parts' keys joined, and no
    # name is longer than the longest name.
    def tail_start(parts)
      named_tail(parts.map { |part| key(part) }) || mentioning_tail(parts.map { |part| part.scan(WORD) })
    end

    def named_tail(keys)
      longest = (@names + @domains).map(&:length).max.to_i
      tail = +""
      found = nil
      (keys.size - 1).downto(1) do |index|
        tail.prepend(keys[index])
        break if tail.length > longest

        found = index if site_tail_key?(tail)
      end
      found
    end

    def mentioning_tail(words)
      following = []
      (words.size - 1).downto(1) do |index|
        return index if domain_from?(words[index] + following, words[index].size)

        following = (words[index] + following).first(MAX_DOMAIN_WORDS - 1)
      end
      nil
    end

    # A declared name may go on with a slogan the title leaves out ("Giełda
    # odpadów" for "Giełda odpadów → Dziennik Gospodarki").
    def site_tail?(text)
      site_tail_key?(key(text))
    end

    def site_tail_key?(key)
      !key.empty? && (@domains.include?(key) || @names.include?(key) ||
        (key.length >= MIN_PREFIX && @names.any? { |name| name.start_with?(key) }))
    end

    def mentions_domain?(text)
      words = text.scan(WORD)
      domain_from?(words, words.size)
    end

    # A label of a few letters alone is most often a word of the title
    # ("in" for in.gov, "nu" for nu.nl), unless the title writes it with
    # capitals after its first letter, as it does acronyms ("AXA", "iA").
    def domain_from?(words, starts)
      brand, spelled = @domains
      (0...starts).any? do |start|
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

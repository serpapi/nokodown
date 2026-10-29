# frozen_string_literal: true

module Nokodown
  # Lines of links to the site's own tag, category and label archives:
  # "Tags: a, b", "Labels: Sea", a category kicker above the title. They
  # say where the page is filed, not what it says. Text between the links
  # (a date, an author) makes the line a byline, which stays. On an archive
  # page such lines are its listing, so nothing goes there.
  module Taxonomy
    PATH = %r{/(?:tags?|categor(?:y|ies)|labels?|topics)/[^/?#]}i.freeze
    QUERY = /[?&](?:cat|tag)=[^&#]/.freeze
    REL = /(?<![\w-])(?:tag|category)(?![\w-])/i.freeze
    ADDRESS = %r{\A(?:https?:)?//(?:www\.)?([^/?#:]+)[^/?#]*}i.freeze
    MAX_LABEL = 24
    MIN_REPEATS = 3
    LABEL = /[:：]\z/.freeze
    # Separators, and the counts an archive widget puts after each link.
    BETWEEN = /\A(?:[\s,;|·•\/–—-]|\(\d+\))*\z/.freeze
    # A grid of category tiles, a titled box or a list of topics is a
    # section of the page, which an index page is made of.
    SECTION = "img, picture, h1, h2, h3, h4, h5, h6, li"
    LISTS = %w[ul ol li dl table tr td].freeze

    module_function

    # Keys of the outermost elements that hold only such a line. Lines of
    # one shape repeated are the category of every card in a listing, or
    # the facts of a product linked to their filters ("Roof: gable"), so
    # they stay.
    def blocks(body, url)
      page = url.to_s
      return Set.new if page.match?(PATH) || page.match?(QUERY)

      site = page[ADDRESS, 1]&.downcase || Breadcrumbs.site_host(body.css("a[href]"))
      judged = {}
      lines = body.css("a[href]").filter_map { |link| outermost(link, site, judged) if archive?(link, site) }
      lines = lines.uniq { |node| Dom.key(node) }
      repeated = lines.group_by { |node| shape(node) }.select { |_, alike| alike.size >= MIN_REPEATS }.keys
      lines.reject { |node| repeated.include?(shape(node)) }.map { |node| Dom.key(node) }.to_set
    end

    def shape(node)
      "#{node.name}.#{Dom.signature(node)}"
    end

    def archive?(link, site)
      href = link["href"].strip
      host = href[ADDRESS, 1]&.downcase
      return false unless host.nil? || host == site

      local = href.sub(ADDRESS, "")
      link["rel"].to_s.match?(REL) || local.match?(PATH) || local.match?(QUERY)
    end

    def outermost(link, site, judged)
      found = nil
      node = link.parent
      while node&.element? && node.name != "body"
        key = Dom.key(node)
        judged[key] = line?(node, site) unless judged.key?(key)
        break unless judged[key]

        found = node
        node = node.parent
      end
      found
    end

    def line?(node, site)
      return false if LISTS.include?(node.name) || node.at_css(SECTION)

      links = node.css("a[href]")
      return false unless links.all? { |link| archive?(link, site) }

      gaps = Breadcrumbs.gaps(node)
      label?(gaps.first) && gaps.drop(1).all? { |gap| gap.match?(BETWEEN) }
    end

    # "Tags:" leads a line of tags; "Price" before a filter's link is a fact.
    def label?(text)
      text.empty? || (text.length <= MAX_LABEL && text.match?(LABEL))
    end
  end
end

# frozen_string_literal: true

module Nokodown
  # Lines of links to the site's own tag archives ("Tags: a, b", "Labels:
  # Sea") and the category kicker above the title. They say where the page
  # is filed, not what it says. A category line after the title stays: a
  # product's or an event's category is one of its facts. Text between the
  # links (a date, an author) makes the line a byline, which stays too. On
  # an archive page such lines are its listing, so nothing goes there.
  module Taxonomy
    TAG_PATH = %r{/(?:tags?|labels?|topics)/[^/?#]}i.freeze
    ARCHIVE_INDEX = %r{\A(?:https?:)?//[^/?#]+(?:/[^?#]*)?/(?:tags?|labels?|topics|categor(?:y|ies))(?:/|\.\w{2,5})?(?:[?#]|\z)}i.freeze
    # Shops file products under "/product-category/", "/categoria-producto/".
    CATEGORY_PATH = %r{/[^/?#]*[ck]ategor[^/?#]*/[^/?#]}i.freeze
    TAG_QUERY = /[?&]tag=[^&#]/.freeze
    CATEGORY_QUERY = /[?&]cat=[^&#]/.freeze
    CATEGORY_REL = /(?<![\w-])category(?![\w-])/i.freeze
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

    # The outermost elements that hold only such a line. Lines of
    # one shape repeated are the category of every card in a listing, or
    # the facts of a product linked to their filters, so they stay.
    def blocks(body, url)
      page = url.to_s
      return [] if archive_page?(page)

      site = page[ADDRESS, 1]&.downcase || Breadcrumbs.site_host(body.css("a[href]"))
      title = body.at_css("h1")
      judged = {}
      lines = body.css("a[href]").filter_map { |link| outermost(link, site, judged) if archive(link, site) }
      lines = lines.uniq { |node, _| Dom.key(node) }.filter_map { |node, kind| node if kind == :tag || kicker?(node, title) }
      repeated = lines.group_by { |node| shape(node) }.select { |_, alike| alike.size >= MIN_REPEATS }.keys
      lines.reject { |node| repeated.include?(shape(node)) }
    end

    # An archive, or the index of all tags or categories ("/tags?view=popular",
    # "/tags.html", "/category"), is made of such lines.
    def archive_page?(page)
      page.match?(TAG_PATH) || page.match?(CATEGORY_PATH) || page.match?(TAG_QUERY) || page.match?(CATEGORY_QUERY) ||
        page.match?(ARCHIVE_INDEX)
    end

    def shape(node)
      "#{node.name}.#{Dom.signature(node)}"
    end

    # A block of its own before the title, holding only the category.
    def kicker?(node, title)
      title && Dom.block?(node) && Dom.key(node).to_i < Dom.key(title).to_i && Breadcrumbs.gaps(node).first.empty?
    end

    # :tag, :category, or nil for any other link.
    def archive(link, site)
      href = link["href"].strip
      host = href[ADDRESS, 1]&.downcase
      return unless host.nil? || host == site

      local = href.sub(ADDRESS, "")
      rel = link["rel"].to_s
      return :category if rel.match?(CATEGORY_REL) || local.match?(CATEGORY_PATH) || local.match?(CATEGORY_QUERY)

      # Shops mark categories, tags and brands alike with rel="tag", so only
      # the address tells a tag archive.
      :tag if local.match?(TAG_PATH) || local.match?(TAG_QUERY)
    end

    # The outermost line around the link, with its kind.
    def outermost(link, site, judged)
      found = nil
      node = link.parent
      while node&.element? && node.name != "body"
        kind = judge(node, site, judged)
        break unless kind

        found = [node, kind]
        node = node.parent
      end
      found
    end

    # Each tag of a line walks up through the same elements, so each is
    # judged once. The parser's copies of a formatting element share its
    # key, so the node is kept with its verdict and a copy is judged anew.
    def judge(node, site, judged)
      key = Dom.key(node)
      seen = judged[key]
      return seen.last if seen&.first == node

      kind = line(node, site)
      judged[key] = [node, kind]
      kind
    end

    # :tag when every link is a tag, :category when any is a category.
    def line(node, site)
      return if LISTS.include?(node.name) || node.at_css(SECTION)

      kinds = node.css("a[href]").map { |link| archive(link, site) }
      return if kinds.include?(nil)

      gaps = Breadcrumbs.gaps(node)
      return unless gaps.drop(1).all? { |gap| gap.match?(BETWEEN) }
      return unless gaps.first.empty? ? Dom.block?(node) : label?(gaps.first)

      kinds.include?(:category) ? :category : :tag
    end

    # "Tags:" leads a line of tags; "Price" before a filter's link is a fact.
    # A line without a label is a block of its own: an inline one is the
    # value of a label outside it.
    def label?(text)
      text.empty? || (text.length <= MAX_LABEL && text.match?(LABEL))
    end
  end
end

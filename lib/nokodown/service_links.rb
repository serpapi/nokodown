# frozen_string_literal: true

module Nokodown
  # Links to what the site does for a visitor rather than to its pages: sign
  # in, register, the account, the cart and the feeds. Whatever their label
  # ("Connexion", "您需要登录后才可以回帖", "View Cart (0)", "Posts (Atom)"),
  # where they point says what they are, so a block holding only such links
  # and a short prompt is furniture in any language. They go once the
  # content is chosen, so their few characters never sway that choice.
  module ServiceLinks
    # The last path segment, without a file extension: "/login", "/cart.asp",
    # "/users/sign_in", "/wp-login.php". A card's "/cart/add?id=1" adds a
    # product, which is the card's own control.
    SERVICE_SEGMENT = /
      \A(?:log[-_]?in|log[-_]?on|log[-_]?out|sign[-_]?in|sign[-_]?on|sign[-_]?up|sign[-_]?out|wp-login|
      register|registration|lost[-_]?password|forgot[-_]?password|reset[-_]?password|password[-_]?reset|
      my[-_]?account|anmelden|registrieren|mein-konto|connexion|inscription|mon-compte|iniciar-sesion|
      mi-cuenta|cadastro|minha-conta|accedi|registrati|registrazione|il-mio-account|inloggen|
      registreren|mijn-account|vhod|registraciya|registratsiya|logowanie|rejestracja|moje-konto|uye-ol|
      hesabim|dang-nhap|dang-ky|tai-khoan|
      cart|basket|checkout|wishlist|carrito|carrinho|panier|warenkorb|carrello|winkelwagen|winkelmand|korzina|
      koszyk|sepet|gio-hang|keranjang)(?:\.[a-z]{2,5})?\z
    /xi.freeze
    # "/feed/", "/rss.xml", "/news.rss"; Blogger's are under "/feeds/".
    FEED_SEGMENT = /\A(?:feeds?|rss2?|atom)\z|\.(?:rss|atom)\z|\A(?:rss|atom|feed)\.xml\z/i.freeze
    FEEDS = "feeds"
    # After a tag or a category the segment names the term: "/tag/atom/".
    ARCHIVE_SEGMENT = /\A(?:tags?|labels?|topics?|categor(?:y|ies)|cat)\z/i.freeze
    # Forum and shop engines name the action in the query: Discuz
    # "member.php?mod=logging", phpBB "ucp.php?mode=register", OpenCart
    # "route=account/login", Bitrix "?login=yes", WordPress "?feed=rss2".
    SERVICE_QUERY = %r{
      [?&](?:mod|mode|action|act|do|route|controller|view|task|option)=[\w/.-]*?
      (?:login|logging|logon|logout|register|registration|signin|signup|lostpassword|authentication|cart|checkout)(?![a-z])|
      [?&](?:login|register|logout)=yes|[?&]feed=(?:rss2?|atom)|[?&](?:format|type)=(?:rss|atom)(?![a-z])
    }xi.freeze
    FRAGMENT = /#.*/m.freeze
    PROMPT = 40
    MAX_LINKS = 6
    ITEMS = %w[li dt dd tr td th].freeze
    UNLINKED_TEXT = ".//text()[not(ancestor::a[@href])]"
    # A table, a video or a picture beside the links is what they sit by;
    # a linked icon is the link's label.
    CONTENT = "table, video, iframe, img, picture"
    NUMBER = /\d/.freeze
    TITLE_SIMILARITY = 0.75

    module_function

    # The outermost elements in the content that hold only service links, at
    # most a handful, and a short prompt. Nothing goes on a page that is
    # itself one of these services: its form and links are what it holds.
    def blocks(roots, url, title)
      return [] if service?(url.to_s.sub(Taxonomy::ADDRESS, ""))

      links = roots.flat_map { |root| root.css("a[href]").to_a }
      site = url.to_s[Taxonomy::ADDRESS, 1]&.downcase || Breadcrumbs.site_host(links)
      tops = roots.map { |root| Dom.key(root) }.to_set
      verdicts = {}
      lines = links.filter_map { |link| line(link, site, tops, title, verdicts) if service_link?(link, site) }
      lines.uniq { |node| Dom.key(node) }
    end

    # A line of its own: links among other words may be part of a sentence,
    # and an item or a span among other links part of a menu, which goes or
    # stays whole.
    def line(link, site, tops, title, verdicts)
      found = Dom.outermost_accepted(link, verdicts) do |node|
        !tops.include?(Dom.key(node)) && holds_only_services?(node, site, title)
      end
      found if found && Dom.block?(found) && !ITEMS.include?(found.name)
    end

    def service_link?(link, site)
      href = link["href"].strip
      host = href[Taxonomy::ADDRESS, 1]&.downcase
      return false unless host.nil? || site.nil? || same_site?(host, site)

      service?(href.sub(Taxonomy::ADDRESS, ""))
    end

    def same_site?(host, site)
      host == site || host.end_with?(".#{site}") || site.end_with?(".#{host}")
    end

    def service?(local)
      path, query = local.sub(FRAGMENT, "").split("?", 2)
      segments = path.to_s.split("/").reject(&:empty?)
      return false if segments[-2].to_s.match?(ARCHIVE_SEGMENT)

      segments.last.to_s.match?(SERVICE_SEGMENT) || segments.last.to_s.match?(FEED_SEGMENT) ||
        segments[0...-1].include?(FEEDS) || "?#{query}".match?(SERVICE_QUERY)
    end

    def holds_only_services?(node, site, title)
      links = node.css("a[href]")
      return false if links.size > MAX_LINKS || !links.all? { |link| service_link?(link, site) }
      return false if node.css(CONTENT).any? { |media| Dom.ancestors_named(media, "a").empty? }

      prompt?(node, title)
    end

    # "您需要登录后才可以回帖", "Subscribe to:": not a heading, the page's
    # title, or a name with a date or a price that the links sit beside.
    def prompt?(node, title)
      prompt = Dom.squish(unlinked_text(node))
      return false if Dom.char_count(prompt) > PROMPT || prompt.match?(NUMBER) || names_page?(prompt, title)

      headings = node.css(Dom::HEADING_SELECTOR).to_a
      headings << node if Dom.heading?(node)
      headings.all? { |heading| Dom.squish(unlinked_text(heading)).empty? }
    end

    def names_page?(prompt, title)
      !title.nil? && !prompt.empty? && Dom.similarity(prompt, title) >= TITLE_SIMILARITY
    end

    def unlinked_text(node)
      node.xpath(UNLINKED_TEXT).map(&:content).join
    end
  end
end

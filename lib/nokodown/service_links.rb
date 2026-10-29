# frozen_string_literal: true

module Nokodown
  # Links to what the site does for a visitor rather than to its pages: sign
  # in, register, the account, the cart and the feeds. Whatever their label
  # ("Connexion", "您需要登录后才可以回帖", "View Cart (0)", "Posts (Atom)"),
  # where they point says what they are, so a block holding only such links
  # and a short prompt is furniture in any language.
  module ServiceLinks
    ADDRESS = %r{\A(?:https?:)?//(?:www\.)?([^/?#:]+)[^/?#]*}i.freeze
    # The last path segment, without a file extension: "/login", "/cart.asp",
    # "/users/sign_in", "/wp-login.php". A card's "/cart/add?id=1" adds a
    # product, which is the card's own control.
    SERVICE_SEGMENT = /
      \A(?:log[-_]?in|log[-_]?on|log[-_]?out|sign[-_]?in|sign[-_]?on|sign[-_]?up|sign[-_]?out|wp-login|
      register|registration|lost[-_]?password|forgot[-_]?password|reset[-_]?password|password[-_]?reset|
      my[-_]?account|anmelden|registrieren|mein-konto|connexion|inscription|mon-compte|iniciar-sesion|
      registro|mi-cuenta|entrar|cadastro|minha-conta|accedi|registrati|registrazione|il-mio-account|inloggen|
      registreren|mijn-account|vhod|registraciya|registratsiya|logowanie|rejestracja|moje-konto|giris|uye-ol|
      hesabim|dang-nhap|dang-ky|tai-khoan|masuk|daftar|
      cart|basket|checkout|wishlist|carrito|carrinho|panier|warenkorb|carrello|winkelwagen|winkelmand|korzina|
      koszyk|sepet|gio-hang|keranjang)(?:\.[a-z]{2,5})?\z
    /xi.freeze
    # Any segment: "/feed/", "/feeds/posts/default", "/rss.xml", "/news.rss".
    FEED_SEGMENT = /\A(?:feeds?|rss|atom)\z|\.(?:rss|atom)\z|\A(?:rss|atom|feed)\.xml\z/i.freeze
    # Forum and shop engines name the action in the query: Discuz
    # "member.php?mod=logging", phpBB "ucp.php?mode=register", OpenCart
    # "route=account/login", Bitrix "?login=yes", WordPress "?feed=rss2".
    SERVICE_QUERY = %r{
      [?&](?:mod|mode|action|act|do|route|controller|view|task|option)=[\w/.-]*?
      (?:login|logging|logon|logout|register|registration|signin|signup|lostpassword|authentication|cart|checkout)(?![a-z])|
      [?&](?:login|register|logout)=yes|[?&]feed=(?:rss2?|atom)|[?&](?:format|type)=(?:rss|atom)(?![a-z])
    }xi.freeze
    PROMPT = 40
    MAX_LINKS = 6
    ITEMS = %w[li dt dd tr td th].freeze

    module_function

    # Keys of the outermost elements that hold only service links, at most a
    # handful, and a short prompt. Nothing goes on a page that is itself
    # one of these services: its form and links are what it holds.
    def blocks(body, url)
      page = url.to_s.sub(ADDRESS, "")
      return Set.new if service?(page)

      site = url.to_s[ADDRESS, 1]&.downcase || Breadcrumbs.site_host(body.css("a[href]"))
      judged = {}
      body.css("a[href]").filter_map { |link| outermost(link, site, judged) if service_link?(link, site) }
          .map { |node| Dom.key(node) }.to_set
    end

    def service_link?(link, site)
      href = link["href"].strip
      host = href[ADDRESS, 1]&.downcase
      return false unless host.nil? || site.nil? || same_site?(host, site)

      service?(href.sub(ADDRESS, ""))
    end

    def same_site?(host, site)
      host == site || host.end_with?(".#{site}") || site.end_with?(".#{host}")
    end

    def service?(local)
      path, query = local.sub(/#.*/m, "").split("?", 2)
      segments = path.to_s.split("/").reject(&:empty?)
      segments.last.to_s.match?(SERVICE_SEGMENT) || segments.any? { |segment| segment.match?(FEED_SEGMENT) } ||
        "?#{query}".match?(SERVICE_QUERY)
    end

    # A line of its own: links among other words may be part of a sentence,
    # and an item or a span among other links part of a menu, which goes or
    # stays whole.
    def outermost(link, site, judged)
      found = nil
      node = link.parent
      while node&.element? && node.name != "body"
        key = Dom.key(node)
        judged[key] = holds_only_services?(node, site) unless judged.key?(key)
        break unless judged[key]

        found = node
        node = node.parent
      end
      found if found && Dom.block?(found) && !ITEMS.include?(found.name)
    end

    def holds_only_services?(node, site)
      links = node.css("a[href]")
      return false if links.size > MAX_LINKS || !links.all? { |link| service_link?(link, site) }

      Dom.char_count(node.content) - links.sum { |link| Dom.char_count(link.content) } <= PROMPT
    end
  end
end

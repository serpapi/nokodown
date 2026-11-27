# frozen_string_literal: true

module Nokodown
  # Forum software prints a panel of member details beside every post:
  # avatar, rank, join date, message and reaction counts. Repeated through a
  # thread it is a sixth of the output, yet its name is all that says who
  # wrote the post. The panel is reduced to one line, "**name**", with the
  # post's date when the panel holds it ("answered Jan 4, 2024").
  module MemberPanel
    HOLDERS = "[itemprop], [class]"
    # "username", "username-coloured" (phpBB), "message-name" (XenForo),
    # "cAuthorPane_author" (Invision).
    NAME_CLASS = /user-?name|(?<![a-z])(?:name|author|poster)(?![\w-])/.freeze
    ITEMPROPS = %w[author name].freeze
    STAMPS = "time, [datetime], [class]"
    DATE_CLASS = /date|time/.freeze
    # Dates that date the member, not the post.
    MEMBER_DATE = /\b(?:joined|join\s?date|member\ssince|registered|last\s(?:seen|active|visit)|local\stime)\b/i.freeze
    MEMBER_DATE_CLASS = /join|regist|last-?(?:seen|active|visit)|local-?time/.freeze
    BY = /(?:by|von|par|por)\s+/i.freeze
    LETTER = /\p{L}/.freeze
    PROFILE = /\b(?:profile|account)\b/i.freeze
    CONTACT = /contact/i.freeze
    # An address in a link's text: a scheme, a "www.", a path, or a domain
    # before a slash.
    ADDRESS = %r{\S*(?:://|www\.)\S*|(?<!\S)\.{0,2}/\S*|\S*\.[a-z]{2,}/\S*}i.freeze
    EMAIL = /\S+@\S+/.freeze
    MAILTO = /\Amailto:/i.freeze
    SCHEME = %r{\A[a-z][a-z0-9+.-]*:(?://)?}i.freeze
    # What an address shows: a file, a domain, a query, a scheme, an email
    # or a board path ("gallery/profile/wren"); not a word ("profile") or a
    # label ("Profile/Account").
    ADDRESS_TEXT = %r{[.?@:]|/.*/}.freeze
    # phpBB's container of a public profile field's value.
    FIELD = "profile-custom-field"
    # An email address the panel gives for the member, which tells apart
    # only from another address, not from a profile.
    IDENTITY = "~"
    MAX_NAME = 60
    MAX_DATE = 50
    # A post's title and by-line come first, within this many characters.
    MAX_HEAD = 200

    module_function

    def panel?(node)
      Dom.signature(node).match?(Patterns::MEMBER_PANEL)
    end

    # A panel with no name, a block of stats, is removed whole. The line a
    # panel PostAttribution marked as a post's leaves carries the post's
    # number and the name's profile link, so that the line can go where the
    # post's own line repeats it (PostAttribution.finish). A line in a link
    # links to the profile, which the post's line does not. Every other line
    # PostAttribution marked a panel for is marked empty: the Pruner reads
    # past the lines that stand in for panels the header used to.
    def reduce(panel)
      name, source = named(panel)
      if name && !bylined?(panel, name)
        line = line(panel.document, name, date(panel, name))
        panel.add_previous_sibling(line)
        repeats(line, panel, name, source) if panel[PostAttribution::PANEL]
        line[PostAttribution::OWN] = PostAttribution::OWN_LINE if panel.key?(PostAttribution::OWN)
      end
      panel.remove
    end

    # A panel whose links leave the name's profile in doubt, or in a link,
    # marks its line empty, as one PostAttribution numbered no post for.
    def repeats(line, panel, name, source)
      number = panel[PostAttribution::PANEL]
      number = "" if !number.empty? && linked?(panel)
      href = profile_href(panel, name, source) unless number.empty?
      line[PostAttribution::REPEAT] = href == false ? "" : [number, href].compact.join(" ")
    end

    # The profile link of the name: the link the name is read from is, or
    # is in ("Wren" and a "Pro" badge in one link), or, without one, the
    # one link the panel holds that says nothing and goes to a page, an
    # avatar's. nil where no link can be the profile ("Send private
    # message", a post count, a menu's "#"); false where it is in doubt:
    # another link says the name and goes elsewhere (a "Referred by" or
    # "Last visitor" of the same name), or several could be the profile.
    def profile_href(panel, name, source)
      # The name's own link is its profile, wherever it sits.
      link = link_around(source, panel) || source.css("a[href]").find { |inner| Dom.text(inner).casecmp?(name) }
      # A contact block's links (phpBB's "View Facebook Profile", a member
      # named Facebook's own Facebook) are ways to reach the member, not the
      # forum's profile, unless one says it is (rel="author").
      links = panel.css("a[href]").reject { |candidate| contact?(candidate, panel) && !author_rel?(candidate) }
      return link ? link["href"] : identity(panel.css("a[href]")) if links.empty?

      # A count ("404" posts, by a member named 404) names no one, nor an
      # address shown as itself (phpBB's "index.php", by a member of that name).
      named = links.select do |candidate|
        Dom.text(candidate).casecmp?(name) && name.match?(LETTER) && !shows_address?(candidate)
      end.map { |candidate| candidate["href"] }
      return false if link.nil? && !named.empty?

      hrefs = link ? [link["href"]] : links.select { |candidate| avatar_link?(candidate) || profile_link?(candidate) }.map { |candidate| candidate["href"] }
      hrefs = (hrefs + named).uniq
      return identity(panel.css("a[href]")) if hrefs.empty?

      hrefs.size == 1 ? hrefs.first : false
    end

    # A panel's email links, contact ones too, where nothing else says who
    # the member is: a co-author's addresses beside a post linked to
    # another address or a profile.
    def identity(links)
      mails = links.map { |candidate| candidate["href"].to_s.strip.delete("\t\n\r") }.select { |href| href.match?(MAILTO) }.uniq
      "#{IDENTITY}#{mails.join("\n")}" unless mails.empty?
    end

    def avatar_link?(link)
      Dom.text(link).empty? && !link["href"].to_s.strip.match?(/\A(?:#|javascript:)/i)
    end

    def contact?(link, panel)
      key = Dom.key(panel)
      node = link.parent
      while node&.element? && Dom.key(node) != key
        return true if Dom.signature(node).match?(CONTACT)

        node = node.parent
      end
      false
    end

    # A link that says it is the profile: rel="author", or "View profile"
    # or "View account 41" in its text or label. An address shown as the
    # text (phpBB's URL fields) says where it goes, not what it is;
    # "Profile/Account" is a label. An email link is a profile only where
    # it says so ("View profile"), not by its address ("account@...").
    def profile_link?(link)
      mail = link["href"].to_s.strip.match?(MAILTO)
      text = shows_address?(link) ? "" : Dom.text(link)
      words = "#{text} #{link['aria-label']} #{link['title']}".gsub(ADDRESS, "")
      words = words.gsub(EMAIL, "") if mail
      author_rel?(link) || words.match?(PROFILE)
    end

    # phpBB's address links, and an email link showing its address, whole
    # or shortened, of any class (phpBB's email fields have none). A link
    # phpBB made of a public field's value is the address the member gave,
    # whatever it shows: the board's own "/profile" page as "profile", or a
    # word the board censors in a shortened address.
    def shows_address?(link)
      href = link["href"].to_s.strip
      field_value?(link, href) || address_link?(link) || (href.match?(MAILTO) && shown?(Dom.text(link), href))
    end

    def field_value?(link, href)
      return false unless href.match?(MAILTO) || link["class"].to_s.split.any? { |name| name.start_with?("postlink") }

      link.ancestors.any? { |ancestor| ancestor.element? && ancestor["class"].to_s.split.include?(FIELD) }
    end

    # A link phpBB made of an address (postlink, postlink-local) shows the
    # address: the end of its href (a board path, "ucp.php?i=profile"), or
    # its start and end around " ... " where it is long, with or without
    # the scheme phpBB adds ("www.", an email). A theme's "View profile" or
    # "profile" button of that class says what it is.
    def address_link?(link)
      classes = link["class"].to_s.split
      return false unless classes.any? { |name| name.start_with?("postlink") }

      text = Dom.text(link)
      href = link["href"].to_s.strip
      # A board's own link shows its path below the board's full URL: a
      # word ("wren") as well, but not one that says it is the profile.
      local = classes.include?("postlink-local") && href.match?(SCHEME) && href.end_with?("/#{text}") && !text.match?(PROFILE)
      return false unless local || text.match?(ADDRESS_TEXT)

      shown?(text, href)
    end

    # The text is the href's end, or its start and end around " ... ": the
    # start's host at least, as a word phpBB censors may differ in the rest.
    # An address has no spaces ("https://example.com/ View profile").
    def shown?(text, href)
      head, tail = text.split(" ... ", 2)
      return href.end_with?(text) unless tail
      return false if head.match?(/\s/) || tail.match?(/\s/)

      start = head.sub(SCHEME, "").downcase
      address = href.sub(SCHEME, "").downcase
      host = lambda { |value| value.split(%r{[/?#]}, 2).first.to_s }
      # Cut inside the host (or an email's address), the start is its start.
      same = start.match?(%r{[/?#]}) ? host.call(start) == host.call(address) : address.start_with?(start)
      !start.empty? && same && href.end_with?(tail)
    end

    def author_rel?(link)
      link["rel"].to_s.downcase.split.include?("author")
    end

    def linked?(panel)
      Dom.ancestors_named(panel, "a").any? { |node| node.key?("href") }
    end

    # The link the source is, or is in, below the panel.
    def link_around(source, panel)
      key = Dom.key(panel)
      node = source
      while node&.element? && Dom.key(node) != key
        return node if node.name == "a" && node.key?("href")

        node = node.parent
      end
      nil
    end

    # The post beside the panel may open with a line naming the poster
    # already, as phpBB's "by name » date" does.
    def bylined?(panel, name)
      by_name = /(?:\A|\s)#{BY}#{Regexp.escape(name)}(?!\w)/i
      panel.parent.element_children.any? do |sibling|
        Dom.key(sibling) != Dom.key(panel) && Dom.text(sibling)[0, MAX_HEAD].match?(by_name)
      end
    end

    # The name, with the element it is read from.
    def named(panel)
      holders = panel.css(HOLDERS).select { |node| name_holder?(node) }
      # A holder around another ("avatar-username" around "username") can
      # hold the name twice, as responsive copies. Each holder's ancestors
      # up to the panel are marked once.
      outer = Set.new
      key = Dom.key(panel)
      holders.each do |holder|
        node = holder.parent
        node = node.parent while node&.element? && Dom.key(node) != key && outer.add?(Dom.key(node))
      end
      holders.reject! { |holder| outer.include?(Dom.key(holder)) }
      holders.each do |holder|
        source = first_link(holder) || holder
        text = name_text(source)
        return [text, source] if text
      end
      link_name(panel)
    end

    def name_holder?(node)
      node["itemprop"].to_s.split.any? { |prop| ITEMPROPS.include?(prop) } || Dom.signature(node).match?(NAME_CLASS)
    end

    # A holder may hold the member's badges too; the profile link is the name.
    def name_text(source)
      text = Dom.text(source)
      text if text.length.between?(1, MAX_NAME)
    end

    # Without a named element, a panel that opens with a link opens with the
    # member's profile link. A block of stats ends with links (location,
    # website) that name no one.
    def link_name(panel)
      link = first_link(panel)
      text = link && Dom.text(link)
      [text, link] if text && text.length <= MAX_NAME && Dom.text(panel).start_with?(text)
    end

    def first_link(node)
      node.css("a[href]").find { |link| Dom.text(link).match?(LETTER) }
    end

    def date(panel, name)
      panel.css(STAMPS).each do |stamp|
        next unless stamp?(stamp)

        text = Dom.text(widened(stamp, panel, name))
        return text if date_text?(text, name) && !text.match?(MEMBER_DATE)
      end
      nil
    end

    def stamp?(node)
      signature = Dom.signature(node)
      return false unless node.name == "time" || node.key?("datetime") || signature.match?(DATE_CLASS)

      !signature.match?(MEMBER_DATE_CLASS) && Dom.text(node).match?(/\d/)
    end

    # The outermost element around the date that stops short of the name,
    # so the line keeps the verb: "answered Jan 4, 2024".
    def widened(stamp, panel, name)
      stamp = stamp.parent while Dom.key(stamp.parent) != Dom.key(panel) && date_text?(Dom.text(stamp.parent), name)
      stamp
    end

    def date_text?(text, name)
      text.length <= MAX_DATE && !text.include?(name)
    end

    def line(document, name, date)
      line = document.create_element("p")
      strong = document.create_element("strong")
      strong.content = name
      line.add_child(strong)
      line.add_child(document.create_text_node(" · #{date}")) if date
      line
    end
  end
end

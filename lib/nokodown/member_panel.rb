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
    # The classes phpBB gives a link it makes of an address; a theme's
    # "postlink-profile" is not one.
    POSTLINKS = %w[postlink postlink-local].freeze
    # Set by Preprocessor on a link phpBB made of an address, which its
    # comments bracket.
    MADE = "data-nokodown-made"
    # Set by Preprocessor on a board's own link to a page in the folder of
    # the page read, the board's root.
    BOARD = "data-nokodown-board"
    # Set by Preprocessor, where the page's URL is known, on a board-style
    # link (postlink-local, or phpBB's "<!-- l -->") that is not below the
    # board's URL: another host or port, or another folder.
    FOREIGN = "data-nokodown-foreign"
    # Set on a plain <dd>: the links of the field rows after it that say
    # the same, read once for all its links.
    COPY = "data-nokodown-copy"
    # phpBB shows a long address as its first 39 characters, " ... " and
    # its last 10, where it is longer than 55.
    PHPBB_CUT = 39
    PHPBB_END = 10
    PHPBB_LONG = 55
    # What names a menu as a theme's own group (its id, role or label).
    NAMES = %w[id role aria-label aria-labelledby aria-describedby aria-description aria-details].freeze
    # Microdata, and RDFa's ("typeof", "property"), mark up a theme's items.
    MICRODATA = %w[itemprop itemscope itemid itemtype typeof property vocab resource about prefix].freeze
    # What marks an element as a theme's own (a "Public office hours"
    # group, an "End of uploader credit" rule): phpBB's carry none.
    THEME = (NAMES + %w[title] + MICRODATA).freeze
    # What names prosilver's "div.contact-icons" as a theme's own: stock
    # menus may carry aria-describedby or aria-labelledby, never these.
    OWN_MENU = (%w[id role aria-label aria-description aria-details title] + MICRODATA).freeze
    # What phpBB's script writes on a dropdown it opens, beside its display.
    PLACED = %w[margin-left margin-right left max-width].freeze
    # What Popper writes on a Bootstrap menu it places.
    POPPER = ["", "position", "inset", "left", "top", "right", "bottom", "margin", "transform"].freeze
    # An email address the panel gives for the member, which tells apart
    # only from another address, not from a profile.
    IDENTITY = "~"
    # Set on a line whose date is read from a contact icon's label
    # ("Office hours (UTC+3)"): shown, but no date of the post's to match.
    LOOSE = "data-nokodown-loose"
    # LOOSE's value for a panel the post's name was read from.
    SOURCE = "source"
    # Set on the line of bootlike's panel (bootlike_panel?), whose post body
    # may open with its rule for narrow screens.
    BOOTLIKE = "data-nokodown-bootlike"
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
        date, loose = date(panel, name)
        line = line(panel.document, name, date)
        # Only prosilver's own panel (dl.postprofile) holds its contact
        # menu; a contact label in a panel known by its id alone, or in a
        # theme's <div class="message-user">, is the panel's own line.
        # prosilver's own fields ("Birthday: 12-05-1987") stand in for its
        # header as main reads them, as do those of a panel the post's name
        # was read from (stock bootlike's); a theme's are kept beside it.
        # A theme that writes its own header in the post body (no
        # prosilver p.author) keeps the field line as base does.
        if loose && panel["class"].to_s.split.include?("postprofile") &&
           (panel.name == "dl" || (panel.name == "div" && panel["id"].to_s.match?(/\Aprofile\d+\z/)))
          if panel.key?(PostAttribution::REPLACED)
            line[LOOSE] = SOURCE
          elsif prosilver_author?(panel)
            line[LOOSE] = panel.name
          end
        end
        panel.add_previous_sibling(line)
        line[BOOTLIKE] = "" if panel[PostAttribution::PANEL] && bootlike_panel?(panel)
        repeats(line, panel, name, source) if panel[PostAttribution::PANEL]
        line[PostAttribution::OWN] = PostAttribution::OWN_LINE if panel.key?(PostAttribution::OWN)
      end
      panel.remove
    end

    # Whether the post beside a prosilver panel reads its name in
    # prosilver's own way: its div.postbody holds a p.author (or none is
    # there to say otherwise). A theme's postbody that writes the name in
    # a header of its own does not.
    def prosilver_author?(panel)
      parent = panel.parent or return true
      bodies = parent.element_children.select { |node| node["class"].to_s.split.include?("postbody") }
      bodies.empty? || bodies.any? { |body| body.css(".author").any? { |author| own_author?(author, body) } }
    end

    # prosilver's p.author heads the post (div.postbody > div#post_contentN
    # > h3, p.author, div.content); a quote's "Guest wrote:" inside the
    # body, or a "Graph prepared by Fern." after its text, does not.
    def own_author?(author, body)
      return false if author.xpath("preceding-sibling::p | preceding-sibling::*[contains(concat(' ', normalize-space(@class), ' '), ' content ')]").any?

      key = Dom.key(body)
      depth = 0
      node = author.parent
      while node&.element? && Dom.key(node) != key
        return false if %w[blockquote q figure cite].include?(node.name) || node["class"].to_s.match?(/quote/i)

        depth += 1
        node = node.parent
      end
      depth <= 1
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
      return link ? link["href"] : person_or_identity(panel, source) if links.empty?

      # A count ("404" posts, by a member named 404) names no one, nor an
      # address shown as itself (phpBB's "index.php", by a member of that name).
      named = links.select do |candidate|
        Dom.text(candidate).casecmp?(name) && name.match?(LETTER) && !shows_address?(candidate)
      end.map { |candidate| candidate["href"] }
      return false if link.nil? && !named.empty?

      # prosilver's contact menu opener ("#", titled "Contact profile")
      # goes nowhere; another "#" link that says it is the profile (a
      # member card's "#member-92") still names someone.
      hrefs = link ? [link["href"]] : links.select { |candidate| !opener?(candidate) && (avatar_link?(candidate) || profile_link?(candidate)) }.map { |candidate| candidate["href"] }
      hrefs = (hrefs + named).uniq
      return person_or_identity(panel, source) if hrefs.empty?

      hrefs.size == 1 ? hrefs.first : false
    end

    def person_or_identity(panel, source)
      id = person_id(panel, source)
      id.nil? ? identity(panel.css("a[href]")) : id
    end

    # A panel marked up as a schema.org Person with no profile link names
    # its member by its itemid ("https://example.com/members/92"): an
    # uploader's card beside a post by /members/72 is another member's.
    # itemtype lists its types apart ("schema.org/Person schema.org/Thing").
    def person_id(panel, source)
      # A holder around the name ("span.username") with the name's own item
      # inside it, the whole of its text: that item is the name's.
      text = Dom.text(source)
      inner = source.css("[itemscope], [typeof]").find { |node| Dom.text(node) == text }
      source = inner if inner
      # The Person the name is in (a "div[itemscope]" around it, RDFa's
      # typeof="Person" resource="/members/92", a colleague's inside the
      # panel's own), else the panel's own; not a Person elsewhere in it
      # (a "Verified by" reviewer's).
      around = person_around(source, panel)
      return around if around

      # The name in an item of its own inside the panel's Person (an
      # unnumbered "colleague") is not the panel's member: in doubt.
      own = microdata_person(panel) || rdfa_person(panel)
      return (item_below?(source, panel) ? false : own) if own

      # A Person elsewhere in it (a "Verified by" reviewer, a "Referral
      # contact") is someone else: the name's own is in doubt.
      false if panel.css("[itemscope], [typeof]").any? { |node| microdata_person(node) || rdfa_person(node) }
    end

    # Whether the node is in an item (microdata or RDFa) below stop.
    def item_below?(node, stop)
      stop_key = Dom.key(stop)
      while node&.element? && Dom.key(node) != stop_key
        return true if node.key?("itemscope") || node.key?("typeof")

        node = node.parent
      end
      false
    end

    # The Person of the nearest item around the node, below stop: nil where
    # that item is something else.
    def person_around(node, stop = nil)
      stop_key = stop && Dom.key(stop)
      while node&.element? && (stop_key.nil? || Dom.key(node) != stop_key)
        return microdata_person(node) || rdfa_person(node) if node.key?("itemscope") || node.key?("typeof")

        node = node.parent
      end
      nil
    end

    def microdata_person(node)
      id = node["itemid"].to_s.strip
      person = node["itemtype"].to_s.split.any? { |type| type.match?(%r{\Ahttps?://schema\.org/Person/?\z}i) }
      id if node.key?("itemscope") && person && !id.empty?
    end

    def rdfa_person(node)
      return unless node.key?("typeof")

      # The typed subject is "about" where given; "resource" is then the
      # object of a relation or property ("knows" /members/72).
      id = (node["about"] || node["resource"]).to_s.strip
      # schema.org's or FOAF's Person: by its prefix, its address, or the
      # vocab in force.
      vocab = ([node] + node.ancestors.to_a).find { |ancestor| ancestor.element? && ancestor.key?("vocab") }
      schema = vocab && vocab["vocab"].to_s.strip.match?(PERSON_VOCAB)
      # Or a prefix of the page's own for it (prefix="s: https://schema.org/"),
      # as the nearest declaration of that prefix binds it: an element's
      # last, its "prefix" over its legacy "xmlns:foaf".
      bound = {}
      ([node] + node.ancestors.to_a).each do |ancestor|
        next unless ancestor.element?

        own = {}
        ancestor.attribute_nodes.each do |attribute|
          own[attribute.name.downcase.delete_prefix("xmlns:")] = attribute.value.to_s.strip if attribute.name.downcase.start_with?("xmlns:")
        end
        ancestor["prefix"].to_s.scan(/(\S+):\s+(\S+)/).each { |name, uri| own[name.downcase] = uri } if ancestor.key?("prefix")
        own.each { |name, uri| bound[name] ||= uri }
      end
      bound["schema"] ||= "https://schema.org/"
      bound["foaf"] ||= "http://xmlns.com/foaf/0.1/"
      prefixes = bound.select { |_, uri| uri.match?(PERSON_VOCAB) }.keys
      person = node["typeof"].to_s.split.any? do |type|
        type.match?(%r{\Ahttps?://(?:schema\.org/|xmlns\.com/foaf/0\.1/)Person/?\z}i) || (schema && type.match?(/\APerson\z/i)) ||
          prefixes.any? { |prefix| type.casecmp?("#{prefix}:Person") }
      end
      id if person && !id.empty?
    end

    # The vocabularies whose "Person" is one: schema.org's and FOAF's.
    PERSON_VOCAB = %r{\A(?:https?://schema\.org/?|https?://xmlns\.com/foaf/0\.1/?)\z}i.freeze

    # A panel's email links, contact ones too, where nothing else says who
    # the member is: a co-author's addresses beside a post linked to
    # another address or a profile.
    def identity(links)
      mails = links.map { |candidate| candidate["href"].to_s.strip.delete("\t\n\r") }.select { |href| href.match?(MAILTO) }.uniq
      "#{IDENTITY}#{mails.join("\n")}" unless mails.empty?
    end

    def avatar_link?(link)
      # An address phpBB made shows its text, blank only where the censor
      # blanked it: an address, not an avatar.
      Dom.text(link).empty? && !nowhere?(link) && !link.key?(MADE)
    end

    def nowhere?(link)
      link["href"].to_s.strip.match?(/\A(?:#|javascript:)/i)
    end

    def opener?(link)
      # prosilver's opener goes nowhere at all ("#"); a theme's
      # "#member-92" or rel="author" goes to the member.
      link["href"].to_s.strip.match?(/\A(?:#?|javascript:.*)\z/im) && link["class"].to_s.split.include?("dropdown-trigger") &&
        !link["rel"].to_s.downcase.split.include?("author")
    end

    def contact?(link, panel)
      return true if bootlike_entry?(link, panel)

      key = Dom.key(panel)
      node = link.parent
      while node&.element? && Dom.key(node) != key
        # A custom field named "contact" is a field, not the contact block.
        if Dom.signature(node).match?(CONTACT) && !node["class"].to_s.split.include?(FIELD)
          # A link that says it is the profile ("View forum profile") is
          # the profile, beside the ways to reach the member; but not an
          # entry of phpBB's contact menu, named as the board's field is
          # ("Chat profile", "View Facebook Profile"), wherever it goes.
          return !profile_link?(link) || menu_entry?(link)
        end

        node = node.parent
      end
      false
    end

    # bootlike's closed Bootstrap menu: "ul.dropdown-menu.dropdown-contents"
    # beside its toggle alone in a "div.dropdown"; Bootstrap marks one it
    # opens "show" and its toggle aria-expanded="true" (the cleanup may
    # have taken the toggle).
    def bootstrap_menu?(node, panel)
      classes = node["class"].to_s.split
      dropdown = node.parent
      return false unless node.name == "ul" && classes.include?("dropdown-menu") && classes.include?("dropdown-contents") &&
                          dropdown&.element? && dropdown.name == "div" && Dom.key(dropdown) != Dom.key(panel)

      outer = dropdown["class"].to_s.split
      toggles = dropdown.element_children.reject { |child| Dom.key(child) == Dom.key(node) }
      # bootlike's group is unnamed; a theme's "Public office hours" group
      # (role="group", a label, a title, microdata) is the theme's.
      return false unless outer.include?("dropdown") && !outer.include?("show") && !expanded?(dropdown, outer) &&
                          THEME.none? { |name| node.key?(name) || dropdown.key?(name) } && toggles.size <= 1

      shown = bootstrap_open?(node, classes, toggles, panel)
      (shown || (!classes.include?("show") && !expanded?(node, classes))) && toggles.all? do |toggle|
        toggle.name == "button" && toggle["class"].to_s.split.include?("dropdown-toggle") && (shown || toggle["aria-expanded"] != "true")
      end
    end

    # bootlike's Bootstrap opened its menu: in its panel ("div#profile3"),
    # right in its "div.btn-group.dropdown", its list is marked "show", and
    # Popper places it; its button, where the cleanup left it, is
    # data-bs-toggle's, "show" and expanded. A theme's list shown so in a
    # panel of its own ("dl.postprofile"), in a row of its own
    # ("div.office-hours"), or by a button of its own, is its group.
    def bootstrap_open?(menu, classes, toggles, panel)
      dropdown = menu.parent
      bootlike_panel?(panel) && Dom.key(dropdown.parent) == Dom.key(panel) && dropdown["class"].to_s.split.include?("btn-group") &&
        classes.include?("show") && !menu.key?("aria-hidden") && toggles.all? do |toggle|
          toggle["data-bs-toggle"] == "dropdown" && toggle["aria-expanded"] == "true" && toggle["class"].to_s.split.include?("show")
        end &&
        menu["style"].to_s.split(";").all? { |pair| POPPER.include?(pair.split(":", 2).first.to_s.strip.downcase) }
    end

    # bootlike's panel: "div#profile3.postprofile" just before the post's
    # "div.postbody"; a theme's card ("dl#user-info", a numbered div beside
    # its "div.article-content") is the theme's, and so is one it marks up
    # as a person ("Co-author" itemprop="author", an uploader's schema.org
    # Person): bootlike's panel has no microdata.
    def bootlike_panel?(panel)
      body = panel.next_element
      row = panel.parent
      box = row&.parent
      panel.name == "div" && panel["id"].to_s.match?(/\Aprofile\d+\z/) && panel["class"].to_s.split.include?("postprofile") &&
        MICRODATA.none? { |key| panel.key?(key) } &&
        body && body.name == "div" && body["class"].to_s.split.include?("postbody") &&
        # Bootlike's panel row always sits in the post's div.card-body.
        row.name == "div" && row["class"].to_s.split.include?("row") &&
        box&.element? && box.name == "div" && box["class"].to_s.split.include?("card-body") &&
        # ... of the post's "div.card#p3".
        numbered?(panel, box.parent, "card")
    end

    # prosilver's contact menu entry: in div.contact-icons, a link of no
    # class but its "last-cell", holding the entry's span.contact-icon. A
    # theme's control (a postlink, or outside that menu) is not one.
    def menu_entry?(link)
      (link["class"].to_s.split - ["last-cell"]).empty? && link.at_css("span.contact-icon") &&
        link.ancestors.any? { |node| node.element? && node["class"].to_s.split.include?("contact-icons") }
    end

    # bootlike's entry: "a.dropdown-item" alone in an "li" of its contact
    # menu, holding the field's "span.<field>-icon" ("Research profile"):
    # a way to reach the member, whatever its field is called.
    def bootlike_entry?(link, panel)
      return false unless link["class"].to_s.split == ["dropdown-item"] && bootlike_panel?(panel)

      item = link.parent
      menu = item&.parent
      item&.element? && item.name == "li" && item.element_children.size == 1 && menu&.element? &&
        link.element_children.size == 1 && link.element_children.first.name == "span" &&
        link.element_children.first["class"].to_s.split.size == 1 && link.element_children.first["class"].to_s.end_with?("-icon") &&
        bootstrap_menu?(menu, panel)
    end

    # A link that says it is the profile: rel="author", or "View profile"
    # or "View account 41" in its text or label. An address shown as the
    # text (phpBB's URL fields) says where it goes, not what it is;
    # "Profile/Account" is a label. An email link is a profile only where
    # it says so ("View profile"), not by its address ("account@...").
    def profile_link?(link)
      mail = link["href"].to_s.strip.match?(MAILTO)
      # Only a text that says "profile" can be an address that does.
      text = Dom.text(link)
      text = "" if text.match?(PROFILE) && shows_address?(link)
      words = "#{text} #{link['aria-label']} #{link['title']}".gsub(ADDRESS, "")
      words = words.gsub(EMAIL, "") if mail
      author_rel?(link) || words.match?(PROFILE)
    end

    # phpBB's address links, and an email link showing its address, whole
    # or shortened, of any class (phpBB's email fields have none). A link
    # phpBB says it made is the address the member gave, whatever it shows:
    # the board's own "/profile" page as "profile", or a word the board
    # censors in a shortened address.
    def shows_address?(link)
      href = link["href"].to_s.strip
      text = Dom.text(link)
      # phpBB's "<!-- l -->" link goes below the board's URL; one that
      # goes elsewhere (FOREIGN) is a theme's, whatever its comments. One
      # the board's (BOARD) is its field whatever the censor did to it.
      return true if link.key?(MADE) && !link.key?(FOREIGN) && ((link[MADE] == "l" && link.key?(BOARD)) || made_text?(text, href, link[MADE])) &&
                     (made_row?(link) || field_row?(link, href, text))
      # In phpBB's own panel (prosilver's, bootlike's), a link phpBB made in
      # a field's row is the field's value, whatever the censor made of the
      # address it shows ("www.old-project ... member-profile", "https://
      # baking.example/public — my-profile"); its member's profile is the
      # name's link, which phpBB does not make.
      return true if link.key?(MADE) && !link.key?(FOREIGN) && (made_row?(link) || field_row?(link, href, text)) && board_panel?(link)

      field_value?(link, href) || address_link?(link) || (href.match?(MAILTO) && shown?(Dom.text(link), href))
    end

    # phpBB's own panel, in the post's own box (prosilver's "div.post",
    # bootlike's "div.card-body"), named by nothing but its "profile<post>"
    # id; a theme's "Co-author" card in that shape is the theme's.
    def board_panel?(link)
      node = link.parent
      node = node.parent while node&.element? && !node["class"].to_s.split.include?("postprofile")
      return false unless node&.element? && (NAMES - ["id"] + ["itemprop"]).none? { |name| node.key?(name) }

      outer = node.parent&.parent
      (prosilver_panel?(node) && outer&.element? && outer.name == "div" && outer["class"].to_s.split.include?("post")) || bootlike_panel?(node)
    end

    # prosilver makes links in a panel only of its fields' values: in a
    # field row, or a plain <dd> as its "field1" row is. A theme's
    # directory action made the same way ("Member directory: wren") names
    # a member.
    def field_row?(link, href, text)
      field_rows(link).any? || field_copy?(link, href, text)
    end

    # The field rows the link sits in, read up its parents (faster than
    # building its ancestors).
    def field_rows(link)
      rows = []
      node = link.parent
      while node&.element?
        rows << node if node["class"].to_s.split.include?(FIELD)
        node = node.parent
      end
      rows
    end

    def plain_row(link)
      [link.parent, link.parent&.parent].find { |node| node&.element? && node.name == "dd" && node["class"].to_s.strip.empty? }
    end

    # prosilver prints its fields' values in <dd> rows, of no class or of
    # its own ("profile-<ident>"); a theme's action between the same
    # comments sits in its own <small>, <div>, or <dd class="coauthor-directory">.
    def made_row?(link)
      [link.parent, link.parent&.parent].any? do |node|
        # An ident is one word ("profile-website", "profile-field1"); a
        # hyphened class is the field row's own ("profile-custom-field",
        # "profile-field-0"), not a theme's "profile-coauthor-directory".
        next false unless node&.element?

        (node.name == "dd" &&
          node["class"].to_s.split.all? { |name| name.match?(/\Aprofile-(?:[a-z0-9_]+|[a-z0-9_-]*field[a-z0-9_-]*)\z/) }) ||
          # bootlike's "field1" row: "div.d-none.d-md-block" in its panel.
          (node.name == "div" && node["class"].to_s.split.sort == %w[d-md-block d-none] && node.parent&.element? &&
            node.parent["class"].to_s.split.include?("postprofile") && bootlike_panel?(node.parent))
      end
    end

    # What phpBB shows of an address it made, censored or not: one word,
    # the address's dots, colons, slashes or "@", or the board path the
    # censor turned into words ("profile page"); not a theme's "View forum
    # profile" between the same comments.
    def made_text?(text, href, made = nil)
      # phpBB shows the href itself, or its end, or its start and end
      # around " ... ", censored alike; the censor's words keep their
      # spaces in the href ("profile  page") that the text folds or strips
      # (".../forum/ view profile"). A theme's "Profile" or "View profile
      # for Wren" going to "/members/92" is not in its href.
      return true if text.empty?

      squeezed = href.gsub(/[[:space:]]+/, " ")
      bare = squeezed.sub(SCHEME, "")
      # Whole, or its start ("www."), or its end at a segment ("profile"
      # of ".../profile"), not a word inside one ("profile" of
      # "viewprofile", "Wren" of "/people/Wren.Baker/biography").
      return true if squeezed.start_with?(text) || bare.start_with?(text) ||
                     [squeezed, squeezed.gsub("/ ", "/")].any? { |whole| address_end?(whole, text) }

      # phpBB cuts a "www." address it made at 39 and 10 characters; one
      # cut so is its own whatever the censor made of the href
      # ("https://archive.example.org/..."), of the cut's " ... " ("……",
      # "⋯", "—", "[cut]") or of the tail, which a word replaced after the
      # cut can lengthen ("member-profile"). A theme's caption between the
      # same comments ("www.old.org ... staff account") is not cut so.
      if made == "w" && text[PHPBB_CUT] == " " && text.match?(/\Awww\./i)
        mark, rest = text[(PHPBB_CUT + 1)..].split(" ", 2)
        return true if !mark.to_s.empty? && rest.to_s.length >= PHPBB_END
      end

      # A cut address the censor changed ("contributors/hellr ... profile/ab")
      # keeps the address's start or end, and a word of address, or no
      # space, around the cut; a board may censor the cut itself ("..."
      # to "…").
      head, tail = text.split(/ (?:\.\.\.|…) /, 2)
      return false if tail.nil?

      # Cut whole ("archived profile/~wren-fermentation- ... research-1"):
      # the href's start, past its scheme, and its end.
      starts = !head.empty? && (squeezed.start_with?(head) || bare.start_with?(head))
      ends = !tail.empty? && squeezed.end_with?(tail)
      return true if starts && ends
      # The censor can change a word on both sides of the cut
      # ("ext.example/x/catalog profile ... office account.01.pdf"): each
      # side still keeps a piece of the address (".../", ".01.pdf"). A head
      # that keeps the href's scheme shows an address phpBB cut, whatever
      # the censor did to the rest ("https://retiredlab ... my-profile" for
      # "https://legacy.example.net/ferments/archived").
      scheme = head[SCHEME]
      # phpBB's "www." links (<!-- w -->) go to "http://" and the address
      # it cut ("www.retiredlab ... my-profile" for
      # "http://www.legacy.example.net/ferments/archived"), whatever the
      # censor made of either side ("www.[link removed] ... my-profile",
      # "web." for "www", "media.test" for the whole host). A theme's
      # caption between the same comments going to "https://" is not one.
      return true if made == "w" && squeezed.start_with?("http://")

      kept = (scheme && scheme.casecmp?(squeezed[SCHEME].to_s)) ||
             (shared_address?(head.sub(SCHEME, ""), bare) && shared_address?(tail.reverse, squeezed.reverse))
      return false unless starts || ends || kept

      text.match?(%r{\w[.:/@]+\w}) || [head, tail].none? { |part| part.match?(/\s/) }
    end

    # The two strings start alike up to an address character (a path's
    # "/", a fragment's "#", a query's "?", "=" or "&").
    def shared_address?(one, other)
      size = 0
      size += 1 while size < one.length && size < other.length && one[size] == other[size]
      one[0, size].match?(%r{[.:/@#?=&]})
    end

    def address_end?(whole, text)
      return false unless whole.end_with?(text)

      before = whole[-text.length - 1]
      before.nil? || !before.match?(/[[:alnum:]]/) || !text[0].match?(/[[:alnum:]]/)
    end

    # Without phpBB's comments, a field's link shows its address as phpBB
    # prints it: whole, or cut at 39 and 10.
    def field_value?(link, href)
      mail = href.match?(MAILTO)
      return false unless mail || (href.match?(SCHEME) && link["class"].to_s.split.any? { |name| POSTLINKS.include?(name) })

      text = Dom.text(link)
      return false if text.empty?
      return false unless field_row?(link, href, text)
      return shown?(text, href) if text.include?(" ... ")

      # Whole, an email is its address, a "www." address lacks the
      # "http://" its href has, and a board's own page (postlink-local) is
      # its path, not a word ("profile" of a co-author's ".../92/profile").
      return href.sub(MAILTO, "").casecmp?(text) if mail

      href == text || href == "http://#{text}" ||
        (link["class"].to_s.split.include?("postlink-local") && dd_row?(link) && href.end_with?("/#{text}") && board_path?(link, href, text) &&
          (text.match?(ADDRESS_TEXT) || board_word?(link, href, text)))
    end

    # phpBB prints a panel's field values in <dd> rows; a board's own
    # link shown as its path elsewhere ("Staff directory: Wren.Baker" in a
    # theme's <small>) is a theme's.
    def dd_row?(link)
      [link.parent, link.parent&.parent].any? { |node| node&.element? && node.name == "dd" }
    end

    # A board's own page shown as a word ("profile", "account/settings")
    # is phpBB's where the board sits at the site's root or one folder
    # below ("/forum/"), in phpBB's own field row (its ident's class, or
    # the plain copy); a co-author's ".../members/92/profile" is not.
    def board_word?(link, href, text)
      return false unless board_path?(link, href, text)

      rows = field_rows(link)
      rows.empty? || rows.any? { |node| node["class"].to_s.split.any? { |name| name.match?(/\Aprofile-[a-z_]+\z/) } }
    end

    # The text is the path below the board's URL: at the site's root or
    # one folder below, or in the folder of the page read.
    # ".../directory/92/A.J." is a directory's, not a board's.
    def board_path?(link, href, text)
      return true if link.key?(BOARD)

      !link.key?(FOREIGN) && href.sub(SCHEME, "").delete_suffix("/#{text}").split("/", -1).drop(1).size <= 1
    end

    # prosilver prints a field named "field1" twice: in a plain <dd>, then
    # in its field row among the field rows that follow it, the same text.
    # A link in such a <dd> before a field row that says the same and holds
    # the same link is that field's.
    def field_copy?(link, href, text)
      row = plain_row(link)
      return false unless row

      mark_copies(row) unless row.key?(COPY)
      link.key?(COPY)
    end

    # Marks the row's links its copy rows hold, all at once.
    def mark_copies(row)
      row[COPY] = ""
      said = Dom.text(row)
      copies = {}
      sibling = row.next_element
      while sibling && sibling["class"].to_s.split.include?(FIELD)
        sibling.css("a").each { |other| copies[[other["href"].to_s.strip, Dom.text(other)]] = true } if Dom.text(sibling) == said
        sibling = sibling.next_element
      end
      return if copies.empty?

      row.css("a").each { |link| link[COPY] = "" if copies.key?([link["href"].to_s.strip, Dom.text(link)]) }
    end

    # A link phpBB made of an address (postlink, postlink-local) shows the
    # address: the end of its href (a board path, "ucp.php?i=profile"), or
    # its start and end around " ... " where it is long, with or without
    # the scheme phpBB adds ("www.", an email). A theme's "View profile" or
    # "profile" button of that class says what it is.
    def address_link?(link)
      classes = link["class"].to_s.split
      return false unless classes.any? { |name| POSTLINKS.include?(name) }

      text = Dom.text(link)
      href = link["href"].to_s.strip
      # A board's own link shows its path below the board's full URL: a
      # word ("wren") as well, in a field row, but not one that says it is
      # the profile.
      local = classes.include?("postlink-local") && dd_row?(link) && href.match?(SCHEME) && href.end_with?("/#{text}") && board_path?(link, href, text)
      return false unless (local && (text.match?(ADDRESS_TEXT) || (!text.match?(PROFILE) && field_row?(link, href, text)))) || text.match?(ADDRESS_TEXT)
      # Another address phpBB shows whole ("www." without its "http://"),
      # or cut, or a field row's path ("gallery/profile/wren"): not the end
      # of a directory's ".../@Wren.Baker".
      return false unless local || text.include?(" ... ") || href == text || href == "http://#{text}" || href.sub(MAILTO, "").casecmp?(text) ||
                          (text.include?("/") && dd_row?(link) && field_row?(link, href, text) && board_path?(link, href, text))

      shown?(text, href)
    end

    # The text is the href's end, or its start and end around " ... ", as
    # phpBB cuts it. An address has no spaces ("https://example.com/ View
    # profile").
    def shown?(text, href)
      head, tail = text.split(" ... ", 2)
      # An email link shows its address, not the subject or body after it.
      if href.match?(MAILTO)
        href = href.sub(/\?.*/m, "")
        # Whole, it is the address itself, not the end of a longer one.
        return href.sub(MAILTO, "").casecmp?(text) || href.casecmp?(text) unless tail
      end
      return href.end_with?(text) unless tail
      return false if head.match?(/\s/) || tail.match?(/\s/)
      # A scheme shown is the href's ("http://" is not "https://").
      scheme = head[SCHEME]
      return false if scheme && !href.downcase.start_with?(scheme.downcase)
      # Shown without one, it is a "www." address, given "http://".
      return false unless scheme || href.match?(MAILTO) || href.downcase.start_with?("http://")

      start = head.sub(SCHEME, "").downcase
      address = href.sub(SCHEME, "").downcase
      # phpBB cuts an address longer than 55, as shown: with its scheme,
      # but not "http://" before "www." nor "mailto:".
      return false if (scheme ? href : address).length <= PHPBB_LONG

      # Cut inside the host (or an email's address), the start is its start,
      # cut where phpBB cuts: a whole host ("www.forum.org") is not the start
      # of a longer one ("www.forum.org.au").
      cut = address[0, PHPBB_CUT - (head.length - start.length)].to_s
      # The end is phpBB's last 10 characters.
      !start.empty? && head.length == PHPBB_CUT && start == cut && tail == href[-PHPBB_END..].to_s
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
      # A field dates the member only where the panel's line can stand in
      # for a post's; any other panel's line keeps it, as base and main do
      # (a quoted post's "post_date", a reader's "Time zone").
      own = !panel[PostAttribution::PANEL].to_s.empty?
      field = nil
      panel.css(STAMPS).each do |stamp|
        unless stamp?(stamp, own)
          # phpBB's field ("Time zone") dates the member, not the post: the
          # line shows it as main does, loose, so the post's line repeats it.
          # The first field that reads as a date does ("Joined May 2016"
          # before it does not).
          if !field && own && stamp?(stamp, false)
            text = Dom.text(widened(stamp, panel, name))
            field = text if date_text?(text, name) && !text.match?(MEMBER_DATE)
          end
          next
        end

        text = Dom.text(widened(stamp, panel, name))
        next unless date_text?(text, name) && !text.match?(MEMBER_DATE)

        loose = contact_icon?(stamp) && contact_menu?(stamp, panel)
        # A contact label ("24/7"), in a closed menu or an open one, after
        # a field the panel shows ("Time zone: UTC+03:00") stands behind
        # it, as in base's and main's line, whatever the theme names the
        # menu ("Contact methods").
        return [field, true] if field && contact_icon?(stamp)

        return [text, loose]
      end
      return [field, true] if field

      nil
    end

    # prosilver's contact menu ("div.dropdown-contents.contact-icons" in
    # its "div.dropdown") hides the label; a theme's visible row of the
    # same icon, even one styled "dropdown-contents contact-icons" but in
    # no dropdown, shows it.
    def contact_menu?(node, panel)
      node = node.parent
      while node&.element? && Dom.key(node) != Dom.key(panel)
        classes = node["class"].to_s.split
        return bootstrap_menu?(node, panel) if node.name == "ul" && classes.include?("dropdown-menu")

        # prosilver's menu is the dropdown's child and waits closed for its
        # trigger; a theme's group shown open ("open", aria-expanded,
        # display:block, <details open>), or set elsewhere in a dropdown, is
        # the panel's own line.
        if classes.include?("contact-icons") && classes.include?("dropdown-contents")
          dropdown = node.parent
          # prosilver's are two divs, the menu unnamed (no id, role or
          # label) beside the dropdown's pointer alone; a theme's section,
          # a group a button names and controls ("#hours"), or one beside a
          # picker's button and list, is the panel's own line.
          return false if node.name != "div" || expanded?(node, classes) || !dropdown&.element? || dropdown.name != "div" ||
                          Dom.key(dropdown) == Dom.key(panel) || OWN_MENU.any? { |name| node.key?(name) } ||
                          !alone?(node, dropdown) || named_menu?(dropdown, panel)

          outer = dropdown["class"].to_s.split
          # phpBB's own script opens its menu: it writes the dropdown's
          # display ("display: block") and marks its "div.dropdown-container"
          # "dropdown-visible"; a theme's dropdown shown so without that
          # mark ("display:flex" in a container of its own), or in a panel
          # of its own, or in a row of its own ("dd.office-hours"; prosilver's
          # is its "dd.profile-contact"), is open.
          return outer.include?("dropdown") &&
                 !expanded?(dropdown, outer, !(opened?(dropdown) && prosilver_panel?(panel) && contact_row?(dropdown, panel)))
        end

        node = node.parent
      end
      false
    end

    # prosilver's contact menu sits in the panel's "dd.profile-contact".
    # phpBB's row has that class alone and no name; a theme's "Public
    # schedule" row ("dd.profile-contact.office-hours") is the theme's.
    def contact_row?(dropdown, panel)
      row = dropdown.parent&.parent
      row&.element? && row.name == "dd" && row["class"].to_s.split == ["profile-contact"] &&
        THEME.none? { |name| row.key?(name) } && Dom.key(row.parent) == Dom.key(panel)
    end

    # prosilver names none of the dropdown, its container or its row; a
    # theme's "Public office hours" group (role, label, title, RDFa or
    # microdata on any of them) is the panel's own line.
    def named_menu?(dropdown, panel)
      key = Dom.key(panel)
      [dropdown, dropdown.parent, dropdown.parent&.parent].any? do |node|
        node&.element? && Dom.key(node) != key && THEME.any? { |name| node.key?(name) }
      end
    end

    # phpBB's script opened the dropdown: it marks the container "visible"
    # and "dropdown-visible" together and shows the dropdown with jQuery's
    # toggle ("display: block"); the dropdown is unnamed (no id, role or
    # label) and no control in the container says it is expanded, which
    # phpBB's script never writes. A theme's button controlling "#hours",
    # or a theme's container marked "dropdown-visible" alone showing its
    # dropdown as a flex or grid, opens a group of its own.
    def opened?(dropdown)
      node = dropdown.parent
      return false unless node&.element? && node.name == "div"

      classes = node["class"].to_s.split
      (%w[dropdown-container dropdown-visible visible] - classes).empty? && (classes & %w[dropdown-up dropdown-down]).any? &&
        toggled?(dropdown["style"].to_s) && THEME.none? { |name| dropdown.key?(name) || node.key?(name) } &&
        !node.at_css("[aria-expanded=true]")
    end

    # jQuery's toggle shows the dropdown ("display: block"), and phpBB's
    # script places it ("margin-left: -176px", "left", "max-width"); a
    # theme's other declarations ("display:block; gap: 4px") are its own.
    def toggled?(style)
      declarations = style.split(";").map(&:strip).reject(&:empty?).map { |pair| pair.split(":", 2).map { |part| part.to_s.strip.downcase } }
      declarations.include?(%w[display block]) &&
        declarations.all? { |name, value| (name == "display" && value == "block") || PLACED.include?(name) }
    end

    # prosilver's panel: "dl.postprofile" beside the post's "div.postbody",
    # both in its "div.inner"; a theme's dl of that class beside its
    # "div.article-content", in an article of its own, is the theme's.
    def prosilver_panel?(panel)
      holder = panel.parent
      panel.name == "dl" && panel["class"].to_s.split.include?("postprofile") &&
        MICRODATA.none? { |key| panel.key?(key) } &&
        [panel.previous_element, panel.next_element].any? { |side| side && side.name == "div" && side["class"].to_s.split.include?("postbody") } &&
        holder&.element? && holder.name == "div" && holder["class"].to_s.split.include?("inner") &&
        numbered?(panel, holder.parent, "post")
    end

    # phpBB numbers a post's panel for its post: "profile3" in the post's
    # own box "p3" (prosilver's div.post, bootlike's div.card). A theme's
    # panel of phpBB's shape in a box of its own (an "article.message", a
    # "div.post" or "div.card-body" numbered for nothing) is the theme's.
    def numbered?(panel, box, name)
      number = panel["id"].to_s[/\Aprofile(\d+)\z/, 1]
      return false unless !number.nil? && box&.element? && box.name == "div" && box["class"].to_s.split.include?(name)
      return box["id"] == "p#{number}" if box.key?("id")

      # bootlike's fixed navbar moves the number to an empty
      # "div.hiddenanchor#p3" just before the card.
      anchor = box.previous_element
      !anchor.nil? && anchor.name == "div" && anchor["class"].to_s.split == ["hiddenanchor"] && anchor["id"] == "p#{number}" &&
        anchor.children.empty?
    end

    def alone?(menu, dropdown)
      dropdown.element_children.all? do |child|
        Dom.key(child) == Dom.key(menu) || (child.name == "div" && child["class"].to_s.split.include?("pointer"))
      end
    end

    def expanded?(node, classes, styled = true)
      node.name == "details" || node.key?("open") || classes.include?("open") || node["aria-expanded"] == "true" ||
        node["aria-hidden"] == "false" || (styled && node["style"].to_s.match?(/display\s*:\s*(?!none)\w/i))
    end

    # phpBB's contact menu names a field's icon by its ident
    # ("office_time-icon") and labels it with the field's name; a theme's
    # class or itemprop beside it ("quoted-date") says it is a date.
    def contact_icon?(node)
      classes = node["class"].to_s.split
      # bootlike prints the ident's icon alone in its menu's item.
      item = node.name == "span" && node.parent&.element? && node.parent.name == "a" && node.parent["class"].to_s.split.include?("dropdown-item")
      node.name != "time" && !node.key?("datetime") && (classes.include?("contact-icon") || (item && classes.size == 1)) &&
        classes.all? { |name| name == "contact-icon" || name.match?(/\A[a-z_]+-icon\z/) } && !"#{node['id']} #{node['itemprop']}".match?(DATE_CLASS)
    end

    def stamp?(node, own = true)
      signature = Dom.signature(node)
      return false unless node.name == "time" || node.key?("datetime") || signature.match?(DATE_CLASS)
      # A phpBB profile field ("Birthday", "Time zone") dates the member
      # where only its name ("profile-birthdate") says date; phpBB prints
      # its value as text, so a <time> in one is a theme's, and so is
      # another class, an id or an itemprop that says date ("post-date",
      # "datePublished"). phpBB names a field in [a-z_] ("profile-time_zone");
      # "profile-post-date" is not one. phpBB prints a field as a row
      # ("dd.profile-custom-field"); a theme's span of that class ("Signed
      # review, April 27") in a box of its own is the theme's date, and so
      # is a row of that class in a theme's own list (a "dl#user-info", a
      # <dl> in a "div.user-info"): only phpBB's postprofile holds phpBB's
      # rows, prosilver's dd in its dl, and bootlike's div in its div
      # numbered for the post ("profile3"), not a theme's div of that class.
      classes = node["class"].to_s.split
      if own && !node.key?("datetime") && classes.include?(FIELD) && postprofile?(node)
        names = classes.reject { |name| name.match?(/\Aprofile-[a-z_]*\z/) } << node["id"].to_s << node["itemprop"].to_s
        return false unless names.any? { |name| name.downcase.match?(DATE_CLASS) }
      end

      !signature.match?(MEMBER_DATE_CLASS) && Dom.text(node).match?(/\d/)
    end

    def postprofile?(row)
      list = row.parent
      return false unless list&.element? && list["class"].to_s.split.include?("postprofile")
      # phpBB names neither its panel nor its rows (no role, label or
      # itemprop, RDFa or title; its panel's only id is "profile<post>"); a
      # theme's "Review author" card, or its "Date the review was signed"
      # row (property="schema:dateCreated"), is the theme's.
      labels = THEME - ["id"]
      return false if labels.any? { |name| list.key?(name) } || (labels + ["id"]).any? { |name| row.key?(name) }

      # phpBB prints its panel beside the post's body (prosilver's and
      # bootlike's div.postbody, after it in phpBB 3.0); a theme's panel of
      # that class in an aside, or in the post's text, is the theme's; and
      # both in prosilver's "div.inner" or bootlike's "div.row": a review
      # card beside a statement of that class in a section is the theme's.
      return false unless [list.previous_element, list.next_element].any? { |side| side && side.name == "div" && side["class"].to_s.split.include?("postbody") }

      holder = list.parent
      # ... and those in the post's own box: prosilver's "div.post" around
      # its "div.inner", bootlike's "div.card-body" around its "div.row"; a
      # theme's reply ("article.message > div.inner") is the theme's.
      box = holder&.element? ? holder.parent : nil
      holder = holder&.element? && holder.name == "div" ? holder["class"].to_s.split : []
      # bootlike's row is responsive ("profile-custom-field profile-<ident>
      # d-none d-md-block"); a theme's numbered card's row is not.
      (row.name == "dd" && list.name == "dl" && holder.include?("inner") && numbered?(list, box, "post")) ||
        (row.name == "div" && list.name == "div" && holder.include?("row") && box&.element? && box.name == "div" &&
          box["class"].to_s.split.include?("card-body") && numbered?(list, box.parent, "card") &&
          (%w[d-none d-md-block] - row["class"].to_s.split).empty?)
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

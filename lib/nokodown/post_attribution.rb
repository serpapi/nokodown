# frozen_string_literal: true

module Nokodown
  # Writes who posted each post of a thread, and when, as one line before the
  # post's body: "**JGD** · April 2, 2024". The header it comes from (avatar,
  # rank, post count, permalink) is furniture that boilerplate removal drops,
  # which would leave a thread whose replies cannot be told apart.
  #
  # #call reads the attributions before boilerplate removal and marks where
  # they go; #write puts them in once the content is selected, so that the
  # lines, and the headers they replace, do not change what is selected.
  # .finish drops the lines member panels left that repeat them, once the
  # content is pruned, so that those lines do not change what is pruned.
  class PostAttribution
    Post = Struct.new(:node, :date, :author, :placement)
    Placement = Struct.new(:header, :body, :tail)

    DATES = "time, [itemprop~=datePublished], [itemprop~=dateCreated]"
    # "username", "ipsUsername", "bigusername" (vBulletin), "username-coloured"
    # (phpBB), "post-author", "cAuthorPane_author"; not "author-badge" or
    # "author_information", which hold more than the name.
    AUTHOR_CLASS = /
      user-?name(?:-colou?red)?(?![\w-])|
      (?<![a-z])(?:author|author-?name|poster|poster-?name|creator)(?![\w-])
    /x.freeze
    BY = /\A(?:by|von|par|por)\s+|\A@/i.freeze
    AD = /\A#{Patterns::AD_LABEL}\z/.freeze
    # Dates in the member panel beside a post date the member, not the post.
    MEMBER_DATE = /
      (?:joined|join\sdate|member\ssince|registered|last\s(?:seen|active)|
      mitglied\sseit|registriert(?:\sseit)?|membre\sdepuis|inscrit(?:\sle)?|miembro\sdesde|registrado)\W*\z
    /xi.freeze
    # A sibling that ends a post: what the climb passed over before it was
    # the body. A modifier ("has-signature") names a body that has one.
    CLOSING = /(?<![a-z])(?<!has-|with-)(?:signature|footer)(?![a-z])/.freeze
    YEAR = /(?<!\d)(?:19|20)\d\d(?!\d)/.freeze
    ANY_YEAR = /(?<!\d)[12]\d{3}(?!\d)/.freeze
    # A field read as a calendar date: a year beside a month's name or in a
    # numeric date ("Signed April 27, 2024", "2024-04-27", "27/04/2024").
    MONTH = /(?<![a-z])(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|
              sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)(?![a-z])/xi.freeze
    NUMERIC_DATE = %r{(?<!\d)\d{1,4}[-/.]\d{1,2}[-/.]\d{1,4}(?!\d)}.freeze
    # Or a day of the month beside it, in a language whose months it does
    # not name ("27 avril 2024", "2024年4月27日"); not a time ("08:45").
    DAY_OF_MONTH = /(?<![\d:])(?:0?[1-9]|[12]\d|3[01])(?![\d:])/.freeze
    ISO_DATE = /\A\d{4}-\d\d-\d\d/.freeze
    LETTER = /\p{L}/.freeze
    MAX_NAME = 60
    MAX_DATE = 50
    # A post's header (user panel, title, date) is short; text longer than
    # this before the date is a body, as on Q&A sites that sign answers below.
    MAX_HEADER = 300
    # Labels a header may hold besides the name and date: "Posted", "Members".
    MAX_LABELS = 40
    MAX_PANEL = 200
    MIN_BODY = 25
    BODY_TAGS = %w[p blockquote pre table].freeze
    BODY_PROPS = %w[text articleBody].freeze
    BODY_PARTS = (BODY_TAGS + BODY_PROPS.map { |prop| "[itemprop~=#{prop}]" }).join(", ").freeze
    # "message-content", "post-body", "ipsType_richText"; not "text-right".
    BODY_CLASS = /(?<![a-z])(?:body|content|text)(?![\w-])/.freeze
    AUTHOR = "data-nokodown-author"
    DATE = "data-nokodown-date"
    REPLACED = "data-nokodown-replaced"
    SUBJECT = "data-nokodown-subject"
    # A subject's value where it is a heading quoted in the header.
    QUOTED_SUBJECT = "quote"
    # A member's account id on a name (XenForo's data-user-id, a theme's
    # data-member-id).
    ACCOUNTS = %w[data-user-id data-member-id].freeze
    ACCOUNT = ACCOUNTS.map { |attribute| "[#{attribute}]" }.join(", ")
    # A post's heading that repeats the thread's title, which stays in place.
    TITLE = "data-nokodown-title"
    HEADINGS = "h1, h2, h3, h4, h5, h6"
    # The number of the post a body, the line written there, or a member
    # panel belongs to; MemberPanel copies a panel's onto the line it leaves.
    # A body's and a line's give the profile the name links to after it:
    # "3 /members/wren.12/". A panel's number ends in "+" where its column
    # holds more than the panel ("3+"). One attribute each, as every one
    # more on the lines slows the pruning that reads them.
    POST = "data-nokodown-post"
    LINE = "data-nokodown-line"
    PANEL = "data-nokodown-panel"
    REPEAT = "data-nokodown-repeat"
    # The element a numbered post is.
    OWNER = "data-nokodown-owner"
    # A member panel in a post's element, outside its body and not around
    # it, and outside a blockquote, and the line it leaves: the post's line
    # stood for it before the panel was read, and the Pruner weighs what it
    # keeps without it, as it did then. A panel's value is OWN_PANEL, the
    # line's OWN_LINE.
    OWN = "data-nokodown-own"
    OWN_PANEL = ""
    OWN_LINE = "line"
    MORE = "+"
    # Nodes read from a member panel's line to the line written below it
    # for the same post.
    MAX_STEPS = 500
    # What shows in the Markdown with no text of its own: a formula renders
    # its alttext, a box its checkbox, a rule a line.
    SHOWN = %w[img picture video audio iframe embed object svg canvas math input hr].freeze
    SHOWN_PARTS = SHOWN.join(", ").freeze
    SEPARATOR = /\A\s*·\s*/.freeze
    ABSOLUTE = %r{\A[a-z][a-z0-9+.-]*://}i.freeze
    # Every element Patterns::MEMBER_PANEL can match, and few others.
    PANEL_CANDIDATES = %w[user poster author profile].flat_map { |word| ["[class*=#{word} i]", "[id*=#{word} i]"] }.join(", ").freeze
    # "bbCodeBlock--quote", "bbcode_quote", "ipsQuote", Discourse's
    # aside.quote, a "blockquote" class or id, "bbquote", "quotation"; not
    # XenForo's "js-selectToQuote" around a body.
    QUOTE = /(?<![a-z])(?<!to-)(?:block|bb)?quot(?:e|ation)/.freeze
    # Where a quote, or its credit, stands.
    QUOTE_TAGS = %w[blockquote q cite figure figcaption details].freeze
    QUOTE_PARTS = (QUOTE_TAGS + %w[[class] [id] [role]]).join(", ").freeze
    # A reply's body, even one emptied of what it held (a checkbox).
    REPLY_PARTS = %w[p blockquote pre table ul ol].join(", ").freeze
    # Cells, which a line leaves the table's or the list's shape to: a
    # column, a caption, or a row showing a video in a layout table.
    CELLS = %w[td th dt dd].freeze
    # The children each container renders; the renderer skips the rest (a
    # <p> between a table's rows, or between a list's terms).
    RENDERED = {
      "table" => %w[tr thead tbody tfoot], "thead" => %w[tr], "tbody" => %w[tr], "tfoot" => %w[tr],
      "tr" => %w[td th], "dl" => %w[dt dd div]
    }.freeze

    class << self
      # nodes: the content as it is rendered. The line a member panel left
      # goes where its panel held its column alone, nothing shows between it
      # and the line written below it for its post, and nothing of the post
      # shows before it; and only where it says no more: the same poster, at
      # the same profile link, with the same date or none, where the post's
      # line is rendered. A line after the post's names a reply, a quote, an
      # attachment or an editor, one after text may be named by it ("Last
      # edited by", in any language), one beside a rank or "Posts: 41" may
      # say whose they are, and one with a date of its own adds it. A line in
      # a table or a list of terms stays, as the table's shape may hang on
      # it. urls reads the profile links. Returns the nodes to render,
      # without a line that was one.
      def finish(nodes, urls = nil)
        repeats = nodes.flat_map { |node| (node[REPEAT] ? [node] : []) + node.css("[#{REPEAT}]").to_a }
        return nodes if repeats.empty?

        roots = nodes.each_with_index.to_h { |node, index| [Dom.key(node), index] }
        roots.delete(nil)
        removed = repeats.select { |repeat| !repeat[REPEAT].empty? && !cell?(repeat) && repeated?(repeat, nodes, roots, urls) }
        removed.each(&:remove)
        keys = removed.filter_map { |line| Dom.key(line) }.to_set
        nodes.reject { |node| keys.include?(Dom.key(node)) }
      end

      private

      # Nothing shows between the panel's line and the post's line after it.
      def repeated?(repeat, nodes, roots, urls)
        return false unless alone?(repeat)

        number = mark(repeat).first
        node = following(repeat, nodes, roots)
        MAX_STEPS.times do
          if node.nil? || (node.element? && (node[LINE] || node[REPEAT]) && mark(node).first != number)
            return false
          elsif node.element? && node[LINE]
            return rendered?(node, roots) && same_line?(repeat, node, urls) && !preceded?(repeat, node, roots)
          elsif node.element? && (node[REPEAT] || post_subject?(node, repeat))
            node = following(node, nodes, roots)
          elsif node.element?
            return false if SHOWN.include?(node.name) && !responsive_rule?(node)

            node = node.child || following(node, nodes, roots)
          else
            return false if node.text? && Dom.char_count(node.content).positive?

            node = following(node, nodes, roots)
          end
        end
        false
      end

      # The panel held its column alone, with no reply or quote beside it.
      def alone?(repeat)
        !repeat[REPEAT].split(" ", 2).first.end_with?(MORE)
      end

      # A style's rule shown only on a narrow screen, to part the panel's
      # column from the post's (bootlike's <hr> alone in a "d-md-none"
      # div, first in its "div.postbody", or bootlike 3's "hr.d-md-none"
      # itself first there); a rule shown on every screen, or a theme's
      # narrow-screen rule between two credits, parts what it stands between.
      def responsive_rule?(node)
        return false unless node.name == "hr" && !themed?(node)

        narrow = ->(element) { element["class"].to_s.split.any? { |name| name.match?(/\Ad-(?:sm|md|lg|xl|xxl)-none\z/) } }
        holder = node.parent
        return true if header_rule?(holder)

        # bootlike 3: the rule is the narrow-screen element.
        holder, node = node, holder if narrow.call(node) && holder&.element? && holder["class"].to_s.split.include?("postbody")
        body = holder&.parent
        panel = body&.element? ? body.previous_element : nil
        # bootlike 3.0.5 prints its wide-screen divider, an empty
        # "div.vr.d-none.d-md-block", just before it.
        first = body&.element? ? body.element_children.first : nil
        first = first.next_element while first && first.name == "div" && first.element_children.empty? &&
                                          Dom.text(first).empty? && first["class"].to_s.split.include?("vr") &&
                                          first["class"].to_s.split.include?("d-none")
        holder&.element? && (holder.name == "hr" || holder.element_children.size == 1) && narrow.call(holder) && !themed?(holder) &&
          body&.element? && body.name == "div" && body["class"].to_s.split.include?("postbody") &&
          first && Dom.key(first) == Dom.key(holder) && panel && panel.key?(MemberPanel::BOOTLIKE)
      end

      # A rule a theme names ("End of uploader credit") parts what it
      # stands between; bootlike's carry no name.
      def themed?(node)
        MemberPanel::THEME.any? { |name| node.key?(name) }
      end

      # bootlike 3.0.5's faint rule under the post's heading
      # ("div.opacity-50 > hr.m-0"), first in its "div#post_content3" in
      # the "div.postbody" beside a bootlike panel's line, once the heading
      # is the post's line.
      def header_rule?(holder)
        content = holder&.element? ? holder.parent : nil
        body = content&.element? ? content.parent : nil
        panel = body&.element? ? body.previous_element : nil
        rule = holder&.element? ? holder.first_element_child : nil
        holder&.element? && holder.name == "div" && holder["class"].to_s.split.include?("opacity-50") &&
          holder.element_children.size == 1 && Dom.text(holder).empty? && !themed?(holder) &&
          rule.name == "hr" && rule["class"].to_s.split.include?("m-0") &&
          content.name == "div" && content["id"].to_s.match?(/\Apost_content\d+\z/) &&
          Dom.key(content.element_children.first) == Dom.key(holder) &&
          body&.element? && body.name == "div" && body["class"].to_s.split.include?("postbody") &&
          panel && panel.key?(MemberPanel::BOOTLIKE)
      end

      # The line is in a table cell, or a list term or definition: without
      # it the renderer may drop the cell, with its column and the table's
      # caption, or read a sparser grid as a layout and drop what its rows
      # show with no text (a video, a formula).
      def cell?(repeat)
        Dom.ancestors_named(repeat, *CELLS).any?
      end

      # Something shows before the panel's line in its post (or, where the
      # panel stands outside the post's element, in what holds it and the
      # post's line), read back from the line up to MAX_STEPS siblings: a
      # forum prints the panel first in the post.
      def preceded?(repeat, line, roots)
        post = Set.new
        owner = owner_of(line)
        panel_owner = owner && owner_of(repeat)
        node = panel_owner && Dom.key(owner) == Dom.key(panel_owner) ? owner : line
        while node&.element?
          post << Dom.key(node)
          node = node.parent
        end
        node = repeat
        MAX_STEPS.times do
          if (previous = node.previous_sibling)
            node = previous
            next unless node.text? || node.element?
            return true if Dom.char_count(node.content).positive?
            return true if node.element? && (SHOWN.include?(node.name) || node.at_css(SHOWN_PARTS))
          else
            node = node.parent
            return false if node.nil? || !node.element? || post.include?(Dom.key(node)) || roots.key?(Dom.key(node))
          end
        end
        true
      end

      # The post element around a line, where PostAttribution numbered it.
      def owner_of(line)
        node = line.parent
        node = node.parent while node&.element? && !node.key?(OWNER)
        node if node&.element?
      end

      # Is the line in the Markdown: below a root through children that
      # each container renders.
      def rendered?(line, roots)
        node = line
        until roots.key?(Dom.key(node))
          parent = node.parent
          return false unless parent&.element?

          children = RENDERED[parent.name] || (definitions?(parent, roots) && RENDERED["dl"])
          return false if children && !children.include?(node.name)

          node = parent
        end
        true
      end

      # A <div> in a <dl> holds terms and definitions, as the <dl> does.
      def definitions?(node, roots)
        while node.name == "div" && !roots.key?(Dom.key(node))
          node = node.parent
          return false unless node&.element?
          return true if node.name == "dl"
        end
        false
      end

      # The node after this one and what it holds, in the order the content
      # is rendered: past the last node of a root, the next root.
      def following(node, nodes, roots)
        until node.element? && (index = roots[Dom.key(node)])
          return node.next_sibling if node.next_sibling

          node = node.parent
          return if node.nil? || !node.element?
        end
        nodes[index + 1]
      end

      # The post's subject, kept where its header went, in a column apart
      # from the panel's line (phpBB's postbody beside its postprofile).
      # One beside the line is a heading the post shows.
      def post_subject?(node, repeat)
        return false unless node[SUBJECT] == "" || node[TITLE] || bootlike_title?(node, repeat)

        key = Dom.key(node.parent)
        repeat.ancestors.none? { |ancestor| ancestor.element? && Dom.key(ancestor) == key }
      end

      # bootlike 4.0.0 links the post's subject to the post
      # ("a.post-title" to "#p4") above its date, beside its panel.
      def bootlike_title?(node, repeat)
        repeat.key?(MemberPanel::BOOTLIKE) && node.name == "a" && node["class"].to_s.split == ["post-title"] &&
          node["href"].to_s.match?(/\A#p\d+\z/) && !themed?(node)
      end

      def same_line?(repeat, line, urls)
        number, href = mark(repeat)
        own_number, own_href = mark(line)
        return false unless number == own_number && same_profile?(href, own_href, urls)

        name, date = parts(repeat)
        own_name, own_date = parts(line)
        return false if name.nil? || own_name.nil?

        # A contact's label read as the date ("Office hours (UTC+3)") is
        # not the post's; a field's calendar date ("Signed April 27, 2024")
        # is the member's own, kept as base and main keep it.
        name.sub(BY, "").strip.casecmp?(own_name) &&
          (date.empty? || (repeat.key?(MemberPanel::LOOSE) && (["dl", MemberPanel::SOURCE].include?(repeat[MemberPanel::LOOSE]) || !calendar?(date))) ||
           date.casecmp?(own_date))
      end

      def calendar?(text)
        # A month with a day or any year ("April 27", "27 Apr 1898"), or a
        # recent year with a day ("2024-04-27", "27 avril 2024").
        (text.match?(MONTH) && (text.match?(DAY_OF_MONTH) || text.match?(ANY_YEAR))) ||
          (text.match?(YEAR) && (text.match?(NUMERIC_DATE) || text.match?(DAY_OF_MONTH)))
      end

      # A line's post number and profile link; "" for a line that names no
      # post.
      def mark(line)
        number, href = (line[LINE] || line[REPEAT]).split(" ", 2)
        [number.to_s.chomp(MORE), href]
      end

      def parts(line)
        strong = line.first_element_child
        return unless strong&.name == "strong"

        name = Dom.text(strong)
        [name, Dom.text(line).delete_prefix(name).sub(SEPARATOR, "")]
      end

      # Two names alike link to the same profile, when both link to one, at
      # the same URL read against the page's: "Wren" and "wren" may be two
      # members, as may /members/WREN and /members/wren, /members/wren/ and
      # /members/wren, one path on two hosts or schemes, ?id=72 and ?id=84,
      # /users#/profiles/191 and /users#/profiles/105, or, without the
      # page's URL, /members/wren and a URL on another site, or ?member=72
      # and /?member=72, which only the page's URL tells apart.
      def same_profile?(href, other, urls)
        return true if href.nil? || other.nil? || href == other
        return same_address?(href, other) if href.start_with?(MemberPanel::IDENTITY) || other.start_with?(MemberPanel::IDENTITY)

        return false unless urls

        target = urls.target(href)
        other_target = urls.target(other)
        !target.nil? && target == other_target && target.match?(ABSOLUTE)
      end

      # A panel's email addresses and the post's link: one member only where
      # they are the same addresses. A co-author's own address beside a
      # shared one (a laboratory's), or an address beside a profile, is
      # another member's, as base and main read it.
      def same_address?(href, other)
        mine, others = [href, other].map do |value|
          addresses = value.start_with?(MemberPanel::IDENTITY) ? value.delete_prefix(MemberPanel::IDENTITY).split("\n") : [value]
          addresses.select { |address| address.match?(MemberPanel::MAILTO) }.map(&:downcase).uniq.sort
        end
        !mine.empty? && mine == others
      end
    end

    def initialize(body)
      @body = body
    end

    def call
      @authors = author_holders
      @titles = @body.css("h1")
      posts = dated_posts.filter_map { |node, date| attributed(node, date) }
      ads, posts = posts.partition { |post| post.author.nil? }
      return self unless dated_above?(posts)

      posts.each { |post| mark(post) }
      mark_member_panels(posts)
      ads.each { |ad| ad.node[REPLACED] = "" }
      self
    end

    # nodes: the selected content. A body selected on its own gets the line
    # inside it.
    def write(nodes)
      bodies = @body.css("[#{AUTHOR}]")
      return if bodies.empty?

      @body.css("[#{REPLACED}]").each do |node|
        node.css("[#{SUBJECT}]").each { |subject| node.add_previous_sibling(subject) }
        node.remove
      end
      selected = nodes.map { |node| Dom.key(node) }
      lines = bodies.map do |body|
        line = line(body[AUTHOR], body[DATE])
        selected.include?(Dom.key(body)) ? body.prepend_child(line) : body.add_previous_sibling(line)
        [line, body]
      end
      Dom.assign_keys(@body)
      # After the key, which is read most.
      lines.each { |line, body| line[LINE] = body[POST] if body[POST] }
    end

    private

    def quoted?(node)
      Dom.ancestors_named(node, "blockquote").any?
    end

    # Each post with the first date in it. A date wrapped in another is read
    # from the inner one, which holds the machine-readable date.
    def dated_posts
      dates = @body.css(DATES).reject { |node| quoted?(node) || node.at_css(DATES) || member_date?(node) }
      @holders = dates.flat_map { |date| date.ancestors.select(&:element?) }.map { |node| Dom.key(node) }.compact.to_set
      @kinds = {}
      posts = dates.each_with_object({}) do |date, found|
        post = post_of(date)
        found[Dom.key(post)] ||= [post, date] if post
      end
      posts = posts.values
      opening = opening_post(dates, posts)
      opening ? [opening] + posts : posts
    end

    # The opening post may stand apart from the replies (Rick Steves:
    # article.topic before section#replies, Vanilla), so it repeats nothing.
    # Keys follow document order.
    def opening_post(dates, posts)
      return if posts.empty?

      first = Dom.key(posts.first[0]).to_i
      replies = posts.flat_map { |post, _| [post] + post.ancestors.select(&:element?) }.map { |node| Dom.key(node) }.to_set
      dates.take_while { |date| Dom.key(date).to_i < first }.each do |date|
        post = opening_of(date, replies)
        return [post, date] if post
      end
      nil
    end

    # The lowest ancestor of the date that names an author and is followed
    # by the replies.
    def opening_of(date, replies)
      date.ancestors.each do |ancestor|
        return if !ancestor.element? || replies.include?(Dom.key(ancestor))

        following = ancestor.next_element
        return ancestor if following && replies.include?(Dom.key(following)) && @authors.include?(Dom.key(ancestor))
      end
      nil
    end

    # Posts repeat: a date's post is its lowest ancestor that has a sibling of
    # the same kind holding a date too, and that names an author.
    def post_of(date)
      date.ancestors.each do |ancestor|
        return if !ancestor.element? || ancestor.name == "body"
        return ancestor if repeated?(ancestor) && @authors.include?(Dom.key(ancestor))
      end
      nil
    end

    # "Joined <time>": the label right before the date, or before the
    # element that holds only the date (<dt>Joined</dt><dd><time></dd>).
    def member_date?(date)
      text = Dom.text(date)
      node = date
      node = node.parent while node.parent.element? && Dom.text(node.parent) == text
      label_before(node).match?(MEMBER_DATE)
    end

    def label_before(node)
      label = +""
      sibling = node.previous_sibling
      while sibling && label.length < MAX_LABELS
        label.prepend(sibling.content)
        sibling = sibling.previous_sibling
      end
      Dom.squish(label)
    end

    # The node holds a date, so it repeats when its parent has another child
    # of its kind that holds one. Counted once per parent: every date in a
    # long thread climbs through the same list of posts.
    def repeated?(node)
      kinds = @kinds[Dom.key(node.parent)] ||= dated_kinds(node.parent)
      kinds.fetch(kind(node), 0) > 1
    end

    def dated_kinds(parent)
      parent.element_children.select { |child| @holders.include?(Dom.key(child)) }.map { |child| kind(child) }.tally
    end

    # The first class, so an opening post marked "b-post--first" still
    # matches the replies' "b-post".
    def kind(node)
      node["class"].to_s.split.first || node.name
    end

    # Keys of the elements that are or hold an author, found in one pass
    # rather than by searching each ancestor on every climb.
    def author_holders
      authors = @body.css("[itemprop~=author], [rel~=author], [class]").select { |node| author?(node) }
      authors.each_with_object(Set.new) do |author, keys|
        ([author] + author.ancestors.to_a).each { |node| break unless node.element? && keys.add?(Dom.key(node)) }
      end
    end

    def author?(node)
      node["itemprop"].to_s.split.include?("author") || node["rel"].to_s.split.include?("author") ||
        Dom.signature(node).match?(AUTHOR_CLASS)
    end

    def attributed(node, date)
      authors = authors_before(node, date)
      return Post.new(node, date) if ad?(authors.first)

      author = authors.find { |candidate| name(candidate) }
      placement = author && placement(date, node)
      Post.new(node, date, author, placement) if placement
    end

    # An ad slot dressed as a post (Invision) is "posted" by "Advertisement":
    # it goes with the headers the lines replace.
    def ad?(author)
      !author.nil? && Dom.text(author).match?(AD)
    end

    # Threads date each post above its body. Q&A sites, and some forum
    # themes, sign it below, where the line would read as the next post's.
    def dated_above?(posts)
      posts.count { |post| text_before(post.date, post.node) * 2 < Dom.text(post.node).length } * 2 > posts.size
    end

    def text_before(date, post)
      node = date
      length = 0
      until Dom.key(node) == Dom.key(post)
        length += preceding_text(node)
        node = node.parent
      end
      length
    end

    def mark(post)
      body = post.placement.body
      body[AUTHOR] = name(post.author)
      shown = date_text(post.date)
      body[DATE] = shown if shown
      subjects = subjects(post, body)
      subjects.each { |subject| subject[SUBJECT] = in_quote?(subject, post.node) ? QUOTED_SUBJECT : "" }
      replaced(post, subjects).each { |node| node[REPLACED] = "" }
    end

    # A heading in the header that holds neither the name nor the date is
    # the post's subject ("Re: The north bridge is closed"); it stays when
    # the header goes, unless it repeats the thread's title, as the opening
    # post's does on vBulletin 5. In a member panel it is the member's rank
    # (XenForo's message-userTitle).
    def subjects(post, body)
      post.node.css(HEADINGS).reject do |heading|
        @authors.include?(Dom.key(heading)) || inside?(post.date, heading) || inside?(heading, body) ||
          quoted?(heading) || repeated_title?(heading) ||
          heading.ancestors.any? { |ancestor| ancestor.element? && MemberPanel.panel?(ancestor) }
      end
    end

    # A quote by role or class ("role=blockquote", div.bbquote) below the
    # post: a heading in it is quoted, not the post's subject. It stays
    # when the header goes, but the walk in finish does not step over it.
    def in_quote?(heading, post_node)
      stop = Dom.key(post_node)
      heading.ancestors.each do |ancestor|
        break if !ancestor.element? || Dom.key(ancestor) == stop
        return true if quote?(ancestor)
      end
      false
    end

    # Marked for the walk in finish, which steps over it as over a subject.
    def repeated_title?(heading)
      return false unless title?(heading)

      heading[TITLE] = ""
      true
    end

    def title?(heading)
      text = Dom.text(heading)
      @titles.any? { |title| Dom.key(title) != Dom.key(heading) && Dom.text(title) == text }
    end

    # The line stands in for the header it was read from: the date line, the
    # panel around the name, and copies of the date above the body.
    def replaced(post, subjects)
      placement = post.placement
      header = placement.header if repeats?(placement, post.author, post.date, subjects)
      [header, author_panel(post.author, post.date, placement.body, subjects), *copies(post.node, post.date, placement.body)].compact
    end

    # The member panel beside a post (XenForo's message-user) names the
    # poster again, and Boilerplate reduces it to a line of its own. Each
    # panel is marked with the post it stands in, or beside in a row that
    # holds that one post, for .finish to weigh the line it leaves against
    # the post's own. A panel in a quote, or beside one, names the quoted
    # poster. A panel that repeats the post's date reads as a post of its
    # own, with the panel's stats for a body: that post's line goes with the
    # panel, and the panel stands beside the post its row holds besides.
    def mark_member_panels(posts)
      panels = @body.css(PANEL_CANDIDATES).select { |node| MemberPanel.panel?(node) }
      return if panels.empty?

      bodies = posts.group_by { |post| Dom.key(post.node) }.transform_values { |group| group.map { |post| post.placement.body } }
      panels.each { |panel| panel[OWN] = "" if own_panel?(panel, bodies) }
      panel_keys = panels.map { |panel| Dom.key(panel) }.to_set
      posts = posts.reject { |post| in_panel?(post, panel_keys) }
      numbers = {}
      accounts = {}
      hrefs = {}
      authors = {}
      names = {}
      posts.each_with_index do |post, index|
        hrefs[index.to_s] = href(post.author)
        authors[index.to_s] = post.author
        post.placement.body[POST] = [index, hrefs[index.to_s]].compact.join(" ")
        post.node[OWNER] = ""
        numbers[Dom.key(post.node)] = index.to_s
        accounts[index.to_s] = account(post.author)
        names[index.to_s] = post.placement.body[AUTHOR]
      end
      rows = rows(posts, numbers)
      kinds = posts.flat_map { |post| post_kinds(post.node) }.to_set
      taken = taken(posts)
      owners = {}
      column_keys = {}
      columns = {}
      holds = {}
      described = described_ids
      panels.each do |panel|
        number = panel_number(panel, numbers, rows, kinds, owners, taken, column_keys, columns, holds)
        post = number&.chomp(MORE)
        named = number && MemberPanel.named(panel)
        number = nil if number && (other_name?(named, names[post]) || other_account?(panel, named, accounts[post]) ||
                                   other_kind?(panel, named, accounts[post], hrefs[post], authors[post]) || described?(panel, described))
        panel[PANEL] = number || ""
      end
    end

    # Climbs from the panel to the posts around it, each with the bodies
    # it holds, and from a body to that post.
    def own_panel?(panel, bodies)
      return false if !panel.key?("class") || quoted?(panel)

      panel_key = Dom.key(panel)
      path = []
      node = panel.parent
      while node&.element?
        path << node
        node = node.parent
      end
      keys = path.map { |ancestor| Dom.key(ancestor) }.to_set << panel_key
      path.any? do |ancestor|
        key = Dom.key(ancestor)
        bodies.fetch(key, []).any? { |body| !keys.include?(Dom.key(body)) && !below?(body, panel_key, key) }
      end
    end

    # Whether the node is the element keyed inner, or below it, under the
    # element keyed outer.
    def below?(node, inner, outer)
      until node.nil? || !node.element? || Dom.key(node) == outer
        return true if Dom.key(node) == inner

        node = node.parent
      end
      false
    end

    # A panel whose name is not the poster's names someone else (a source's
    # supplier, Annette beside Ann, an officer whose role mentions the
    # poster): its line can never repeat the post's, so it is not one the
    # post's line replaces.
    def other_name?(named, name)
      return true if name.nil?

      text, = named
      text.nil? || !Dom.squish(Dom.squish(text).sub(BY, "")).casecmp?(Dom.squish(name))
    end

    # The account id a forum gives a name (XenForo's data-user-id): two
    # names alike with two ids are two members.
    def account(author)
      holder = account_of(author) ? author : author.at_css(ACCOUNT)
      holder ||= account_around(author)
      holder && account_of(holder)
    end

    # A wrapper that holds the name and nothing else ("span.member-ident"
    # with data-member-id="72" around the username's link) gives its id.
    def account_around(author)
      text = Dom.text(author)
      node = author.parent
      while node&.element? && Dom.text(node) == text
        return node if account_of(node)

        node = node.parent
      end
      nil
    end

    def account_of(node)
      ACCOUNTS.each { |attribute| return node[attribute] if node.key?(attribute) }
      nil
    end

    # Every id the node gives: two that differ (data-member-id="92",
    # data-user-id="72") leave it in doubt.
    def accounts_of(node)
      ACCOUNTS.filter_map { |attribute| node[attribute] if node.key?(attribute) }.uniq
    end

    def other_account?(panel, named, account)
      return false unless account

      # The name's own id where it has one: a "Referred by" link in the
      # panel has another member's.
      _, source = named
      named = source && name_account(source, panel)
      return accounts_of(named) != [account] if named

      ids = panel.css(ACCOUNT).map { |node| account_of(node) }
      ids << account_of(panel) if account_of(panel)
      !ids.empty? && !ids.include?(account)
    end

    # A name the panel and the post identify in different ways may be two
    # members, as base and main read them: an unlinked uploader with
    # data-member-id="92" beside a post linking to /members/72, an
    # uploader's Person or mailbox beside a post's account id or a
    # microdata author. A name phpBB prints bare (profiles hidden) beside
    # a panel's email link is one member.
    def other_kind?(panel, named, account, href, author)
      _, source = named
      return false if source.nil? || author.nil? || (account && href)

      panel_account = name_account(source, panel)
      return !panel_account.nil? && MemberPanel.link_around(source, panel).nil? if href
      return false if account && panel_account
      return true if panel_account || MemberPanel.person_id(panel, source).is_a?(String)

      (account || marked?(author)) && !MemberPanel.identity(panel.css("a[href]")).nil?
    end

    # The post's name marked as its author (itemprop="author" around it).
    def marked?(author)
      text = Dom.text(author)
      node = author
      while node&.element? && Dom.text(node) == text
        return true if node["itemprop"].to_s.split.any? { |prop| %w[author creator].include?(prop) }

        node = node.parent
      end
      false
    end

    # The element that gives the name's id: the name's, one in it, one
    # around it, or the panel's own (a "Referred by" link in it has another
    # member's).
    def name_account(source, panel)
      return source if account_of(source)

      inner = source.at_css(ACCOUNT)
      return inner if inner

      key = Dom.key(panel)
      node = source.parent
      while node&.element? && Dom.key(node) != key
        return node if account_of(node)

        node = node.parent
      end
      panel if account_of(panel)
    end

    # Ids an element names as what describes or labels it: a panel so
    # named credits that element ("Uploaded by the member above"), not the
    # post.
    def described_ids
      @body.css("[aria-describedby], [aria-labelledby]").each_with_object(Set.new) do |node, ids|
        "#{node['aria-describedby']} #{node['aria-labelledby']}".split.each { |id| ids << id }
      end
    end

    def described?(panel, described)
      return false if described.empty?

      described.include?(panel["id"]) || panel.css("[id]").any? { |node| described.include?(node["id"]) }
    end

    # The number a member panel's line is marked with, or nil where the line
    # stays whatever comes after it: one in a quote, or in no post, or beside
    # a quote in its column.
    def panel_number(panel, numbers, rows, kinds, owners, taken, column_keys, columns, holds)
      return if quote?(panel)

      number = owner(panel, numbers, rows, kinds, owners)
      return unless number

      column = column(panel, taken, column_keys, columns)
      return number if Dom.key(column) == Dom.key(panel)

      held = (holds[Dom.key(column)] ||= column_of(column))
      return if held.quotes.any? { |quote| !inside?(quote, panel) }

      alone_in?(panel, held) ? number : "#{number}#{MORE}"
    end

    # What a member panel's column holds: its non-space characters, what
    # shows with no text, the blocks a reply's body is made of, and the
    # quotes in it.
    Column = Struct.new(:chars, :shown, :parts, :quotes)

    # A quote, or where its credit stands.
    def quote?(node)
      QUOTE_TAGS.include?(node.name) || node["role"].to_s.split.include?("blockquote") || Dom.signature(node).match?(QUOTE)
    end

    # The elements that are or hold a post's date or body: a panel's column
    # stops below them.
    def taken(posts)
      posts.each_with_object(Set.new) do |post, keys|
        [post.date, post.placement.body].each do |node|
          node = node.parent while node&.element? && keys.add?(Dom.key(node))
        end
      end
    end

    # The panel's column: its highest ancestor that holds no post's date or
    # body, or the panel, which then holds its column alone. Elements
    # climbed through are remembered with the key of the column above them,
    # so each is climbed through once.
    def column(panel, taken, column_keys, columns)
      passed = []
      node = panel
      until (key = column_keys[Dom.key(node)])
        passed << Dom.key(node)
        parent = node.parent
        if parent.nil? || !parent.element? || taken.include?(Dom.key(parent))
          key = Dom.key(node)
          columns[key] = node
          break
        end
        node = parent
      end
      passed.each { |passed_key| column_keys[passed_key] = key }
      columns[key]
    end

    def column_of(node)
      quotes = node.css(QUOTE_PARTS).select { |candidate| quote?(candidate) }
      Column.new(Dom.char_count(node.content), shown(node), node.css(REPLY_PARTS).size, quotes)
    end

    def shown(node)
      node.css(SHOWN_PARTS).size + (SHOWN.include?(node.name) ? 1 : 0)
    end

    # The panel holds its column alone: the column holds nothing else, such
    # as a reply the panel's line names.
    def alone_in?(panel, column)
      Dom.char_count(panel.content) == column.chars && shown(panel) == column.shown &&
        panel.css(REPLY_PARTS).size == column.parts
    end

    def in_panel?(post, panel_keys)
      node = post.placement.body
      until Dom.key(node) == Dom.key(post.node)
        return true if panel_keys.include?(Dom.key(node))

        node = node.parent
      end
      panel_keys.include?(Dom.key(node))
    end

    # The number of the one post each ancestor of a post holds, or nil where
    # it holds more, found in one pass, each climb stopping at an ancestor
    # that holds more already.
    def rows(posts, numbers)
      posts.each_with_object({}) do |post, rows|
        post.node.ancestors.each do |node|
          break unless node.element?

          key = Dom.key(node)
          break if rows.key?(key) && rows[key].nil?

          rows[key] = rows.key?(key) ? nil : numbers[Dom.key(post.node)]
        end
      end
    end

    # The innermost post around the panel, or the one post its row holds.
    # A panel in a quote, or in a quote's credit, names the quoted poster,
    # and one in a reply the post holds, undated, names the reply's: an
    # element of a post's kind, in a post, that is no post of its own. One
    # beside the post in its row is the row's other cell. Elements climbed
    # through are remembered with what was found above them, so each is
    # climbed through once.
    def owner(panel, numbers, rows, kinds, owners)
      passed = []
      found = [nil, false, false]
      node = panel.parent
      while node&.element?
        key = Dom.key(node)
        if owners.key?(key)
          found = owners[key]
          break
        end
        if numbers.key?(key) || rows.key?(key)
          found = [numbers[key] || rows[key], numbers.key?(key), false]
          owners[key] = found
          break
        end
        if quote?(node)
          found = [nil, false, false]
          owners[key] = found
          break
        end

        passed << [key, post_kind?(node, kinds)]
        node = node.parent
      end
      number, in_post, reply = found
      passed.reverse_each do |key, kind|
        reply ||= kind
        owners[key] = [number, in_post, reply]
      end
      number unless in_post && reply
    end

    # A post's kind: its tag with each of its classes, and with its id
    # without the number ("post-"). A plain <div> around a panel is no post.
    def post_kinds(node)
      kinds = node["class"].to_s.split.map { |token| [node.name, token] }
      stem = id_stem(node)
      stem ? kinds << [node.name, stem] : kinds
    end

    # An element of a post's kind, whatever classes come with it ("message
    # message--unread", "unread message", "theme-light message").
    def post_kind?(node, kinds)
      return true if node["class"].to_s.split.any? { |token| kinds.include?([node.name, token]) }

      stem = id_stem(node)
      !stem.nil? && kinds.include?([node.name, stem])
    end

    def id_stem(node)
      id = node["id"].to_s
      "##{id.gsub(/\d+/, '')}" if id.match?(/\d/)
    end

    # The profile link of the name the line gives: the link the name is or
    # is in, or the first one it holds.
    def href(author)
      source = name_source(author) || author
      link = source if source.name == "a" && source.key?("href")
      link ||= Dom.ancestors_named(source, "a").find { |node| node.key?("href") }
      link ||= source.css("a[href]").find { |candidate| !Dom.text(candidate).empty? }
      link ? link["href"] : person_scope(source)
    end

    # Without a link, the Person the name is the name of: the nearest
    # item around it ("span[itemprop=author][itemscope]" with
    # itemid="/members/72", or RDFa's typeof="Person" resource=...).
    def person_scope(source)
      MemberPanel.person_around(source)
    end

    # The names before the date, nearest first: a thread's header reads
    # "name, date". Names in quotes belong to the quoted post.
    def authors_before(post, date)
      date_key = Dom.key(date)
      before = post.css("*").take_while { |node| Dom.key(node) != date_key }
      before.reverse.select { |node| author?(node) && !quoted?(node) }
    end

    def name(author)
      text = Dom.text(name_source(author) || author).sub(BY, "")
      text unless text.empty? || text.length > MAX_NAME || label?(text)
    end

    # Where the name is read from: the author's name property, or the first
    # link that says something.
    def name_source(author)
      source = author.at_css("[itemprop~=name]") if author["itemprop"].to_s.split.include?("author")
      source || author.css("a[href]").find { |link| !Dom.text(link).empty? }
    end

    # The Pruner would strip a label ("Loading", "Share") from the line,
    # leaving only its date.
    def label?(text)
      text.match?(Patterns::BOILERPLATE_TEXT)
    end

    # Climbs from the date to the first sibling that holds content: the
    # post's body. The ancestor before it is the post's header, and what the
    # climb passed over after the date ("#1", a share link) is its tail.
    def placement(date, post)
      node = date
      before = 0
      tail = []
      until Dom.key(node) == Dom.key(post)
        before += preceding_text(node)
        return if before > MAX_HEADER

        body = following_body(node, tail)
        return Placement.new(node, body, tail) if body

        node = node.parent
      end
      nil
    end

    def preceding_text(node)
      length = 0
      sibling = node.previous_sibling
      while sibling
        length += Dom.text(sibling).length
        sibling = sibling.previous_sibling
      end
      length
    end

    def following_body(node, tail)
      start = tail.size
      sibling = node.next_sibling
      while sibling
        return short_reply(tail, start) if sibling.element? && closing?(sibling)
        return sibling if sibling.element? && body?(sibling)

        tail << sibling
        sibling = sibling.next_sibling
      end
      nil
    end

    def closing?(node)
      node.name == "footer" || Dom.signature(node).match?(CLOSING)
    end

    # A reply too short to pass for a body ("Agreed.") is the first element
    # beside the signature or footer, before it, with words of its own.
    def short_reply(tail, start)
      index = (start...tail.size).find { |position| tail[position].element? && unlinked_text(tail[position]).match?(LETTER) }
      tail.slice!(index..).first if index
    end

    # A one-word reply ("Agreed.") is found by its class, before the footer
    # or signature after it.
    def body?(node)
      Dom.text(node).length >= MIN_BODY || Dom.signature(node).match?(BODY_CLASS) || prose?(node)
    end

    # Is or holds a paragraph, quote, code or table. Nokolexbor answers
    # matches? by searching the whole document, so the node itself is
    # checked by its name.
    def prose?(node)
      BODY_TAGS.include?(node.name) || node["itemprop"].to_s.split.any? { |prop| BODY_PROPS.include?(prop) } ||
        !node.at_css(BODY_PARTS).nil?
    end

    # The header goes when the line says all it said: besides the name, the
    # date and the subject, which stays, it holds a few labels, and after the
    # date only links and numbers ("#1"), not a short reply.
    def repeats?(placement, author, date, subjects)
      return false if placement.tail.any? { |node| unlinked_text(node).match?(LETTER) }

      header = placement.header
      labels = Dom.text(header).length - Dom.text(date).length
      labels -= Dom.text(author).length if inside?(author, header)
      labels -= subjects.sum { |subject| inside?(subject, header) ? Dom.text(subject).length : 0 }
      labels <= MAX_LABELS
    end

    # The highest ancestor of the name that holds neither the date nor the
    # body: its avatar, rank and post count, when that is all it holds
    # besides the post's subject.
    def author_panel(author, date, body, subjects)
      taken = (date.ancestors.to_a + [body] + body.ancestors.to_a).select(&:element?).map { |node| Dom.key(node) }.to_set
      return if taken.include?(Dom.key(author))

      panel = author
      panel = panel.parent until taken.include?(Dom.key(panel.parent))
      length = Dom.text(panel).length - subjects.sum { |subject| inside?(subject, panel) ? Dom.text(subject).length : 0 }
      panel if length <= MAX_PANEL && !prose?(panel)
    end

    def inside?(node, container)
      ([node] + node.ancestors.to_a).any? { |ancestor| Dom.key(ancestor) == Dom.key(container) }
    end

    def unlinked_text(node)
      return node.content if node.text?
      return "" if !node.element? || node.name == "a"

      node.children.map { |child| unlinked_text(child) }.join
    end

    # Some themes show the date again above the body ("April 2, 2024 1 yr"):
    # the outermost element around each copy that holds nothing else, short
    # of the body. A copy inside a phrase ("Posted April 2, 2024") stays, or
    # the phrase would lose its date, and so does one in a quote, one after
    # the body's first words, and one that is all the body holds: a reply
    # that is a date.
    def copies(post, date, body)
      stamp = date["datetime"] || date["content"]
      return [] if stamp.nil?

      stops = [Dom.key(post), Dom.key(body)]
      post.css(DATES).filter_map do |copy|
        next if Dom.key(copy) == Dom.key(date) || (copy["datetime"] || copy["content"]) != stamp || quoted?(copy)

        line = copy
        line = line.parent while !stops.include?(Dom.key(line.parent)) && Dom.text(line.parent) == Dom.text(copy)
        line if Dom.key(line) != Dom.key(copy) && above?(line, body)
      end
    end

    # Before the body, or first in it with more of the post after it. Keys
    # follow document order.
    def above?(line, body)
      return false if inside?(body, line)
      return Dom.key(line).to_i < Dom.key(body).to_i unless inside?(line, body)

      text_before(line, body).zero? && Dom.text(body).length > Dom.text(line).length
    end

    # The date as the page shows it when that is a full date. "1 yr" or
    # "10 hours ago" depends on when the page was saved, so the machine
    # readable date replaces it, without its time down to the millisecond.
    # Without one, the date the page shows ("Yesterday at 10:40") is all
    # there is, and the header the line replaces showed it.
    def date_text(date)
      shown = [Dom.text(date)] + date.element_children.map { |child| Dom.text(child) } + [Dom.squish(date["title"].to_s)]
      text = shown.find { |candidate| candidate.length <= MAX_DATE && candidate.match?(YEAR) }
      return text unless text.nil? || text.match?(ISO_DATE)

      (text || date["datetime"] || date["content"]).to_s[ISO_DATE] || (shown.first if shown.first.length.between?(1, MAX_DATE))
    end

    def line(name, date)
      document = @body.document
      line = document.create_element("p")
      strong = document.create_element("strong")
      strong.content = name
      line.add_child(strong)
      line.add_child(document.create_text_node(" · #{date}")) if date
      line
    end
  end
end

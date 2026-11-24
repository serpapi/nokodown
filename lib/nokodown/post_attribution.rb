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
    # the body.
    CLOSING = /(?<![a-z])(?:signature|footer)(?![a-z])/.freeze
    YEAR = /(?<!\d)(?:19|20)\d\d(?!\d)/.freeze
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

    def initialize(body)
      @body = body
    end

    def call
      @authors = author_holders
      posts = dated_posts.filter_map { |node, date| attributed(node, date) }
      ads, posts = posts.partition { |post| post.author.nil? }
      return self unless dated_above?(posts)

      posts.each { |post| mark(post) }
      ads.each { |ad| ad.node[REPLACED] = "" }
      self
    end

    # nodes: the selected content. A body selected on its own gets the line
    # inside it.
    def write(nodes)
      bodies = @body.css("[#{AUTHOR}]")
      return if bodies.empty?

      @body.css("[#{REPLACED}]").each(&:remove)
      selected = nodes.map { |node| Dom.key(node) }
      bodies.each do |body|
        line = line(body[AUTHOR], body[DATE])
        selected.include?(Dom.key(body)) ? body.prepend_child(line) : body.add_previous_sibling(line)
      end
      Dom.assign_keys(@body)
    end

    private

    def quoted?(node)
      Dom.ancestors_named(node, "blockquote").any?
    end

    # Each post with the first date in it. A date wrapped in another is read
    # from the inner one, which holds the machine-readable date.
    def dated_posts
      dates = @body.css(DATES).reject { |node| quoted?(node) || node.at_css(DATES) || member_date?(node) }
      holders = dates.flat_map { |date| date.ancestors.select(&:element?) }.map { |node| Dom.key(node) }.compact.to_set
      posts = dates.each_with_object({}) do |date, found|
        post = post_of(date, holders)
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
    def post_of(date, holders)
      date.ancestors.each do |ancestor|
        return if !ancestor.element? || ancestor.name == "body"
        return ancestor if repeated?(ancestor, holders) && @authors.include?(Dom.key(ancestor))
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

    def repeated?(node, holders)
      key = Dom.key(node)
      node.parent.element_children.any? do |sibling|
        Dom.key(sibling) != key && holders.include?(Dom.key(sibling)) && kind(sibling) == kind(node)
      end
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
      replaced(post).each { |node| node[REPLACED] = "" }
    end

    # The line stands in for the header it was read from: the date line, the
    # panel around the name, the member panels beside the post, and copies
    # of the date above the body.
    def replaced(post)
      placement = post.placement
      header = placement.header if repeats?(placement, post.author, post.date)
      [header, author_panel(post.author, post.date, placement.body), *member_panels(post.node, placement.body),
       *copies(post.node, post.date)].compact
    end

    # The member panel beside a post (XenForo's message-user) names the
    # poster as well when the name is read from the header: Boilerplate
    # would reduce it to a second line.
    def member_panels(post, body)
      post.css("[class]").select do |node|
        MemberPanel.panel?(node) && !quoted?(node) && !inside?(node, body) && !inside?(body, node)
      end
    end

    # The names before the date, nearest first: a thread's header reads
    # "name, date". Names in quotes belong to the quoted post.
    def authors_before(post, date)
      date_key = Dom.key(date)
      before = post.css("*").take_while { |node| Dom.key(node) != date_key }
      before.reverse.select { |node| author?(node) && !quoted?(node) }
    end

    def name(author)
      source = author.at_css("[itemprop~=name]") if author["itemprop"].to_s.split.include?("author")
      source ||= author.css("a[href]").find { |link| !Dom.text(link).empty? }
      text = Dom.text(source || author).sub(BY, "")
      text unless text.empty? || text.length > MAX_NAME || label?(text)
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

    # The header goes when the line says all it said: besides the name and
    # the date it holds a few labels, and after the date only links and
    # numbers ("#1"), not a short reply.
    def repeats?(placement, author, date)
      return false if placement.tail.any? { |node| unlinked_text(node).match?(LETTER) }

      header = placement.header
      labels = Dom.text(header).length - Dom.text(date).length
      labels -= Dom.text(author).length if inside?(author, header)
      labels <= MAX_LABELS
    end

    # The highest ancestor of the name that holds neither the date nor the
    # body: its avatar, rank and post count, when that is all it holds.
    def author_panel(author, date, body)
      taken = (date.ancestors.to_a + [body] + body.ancestors.to_a).select(&:element?).map { |node| Dom.key(node) }.to_set
      return if taken.include?(Dom.key(author))

      panel = author
      panel = panel.parent until taken.include?(Dom.key(panel.parent))
      panel if Dom.text(panel).length <= MAX_PANEL && !prose?(panel)
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
    # the outermost element around each copy that holds nothing else. A copy
    # inside a phrase ("Posted April 2, 2024") stays, or the phrase would
    # lose its date.
    def copies(post, date)
      stamp = date["datetime"] || date["content"]
      return [] if stamp.nil?

      post.css(DATES).filter_map do |copy|
        next if Dom.key(copy) == Dom.key(date) || (copy["datetime"] || copy["content"]) != stamp

        line = copy
        line = line.parent while Dom.key(line.parent) != Dom.key(post) && Dom.text(line.parent) == Dom.text(copy)
        line unless Dom.key(line) == Dom.key(copy)
      end
    end

    # The date as the page shows it when that is a full date. "1 yr" or
    # "10 hours ago" depends on when the page was saved, so the machine
    # readable date replaces it, without its time down to the millisecond.
    def date_text(date)
      shown = [Dom.text(date)] + date.element_children.map { |child| Dom.text(child) } + [Dom.squish(date["title"].to_s)]
      text = shown.find { |candidate| candidate.length <= MAX_DATE && candidate.match?(YEAR) }
      return text unless text.nil? || text.match?(ISO_DATE)

      (text || date["datetime"] || date["content"]).to_s[ISO_DATE]
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

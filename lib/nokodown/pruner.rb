# frozen_string_literal: true

module Nokodown
  # Final cleanup inside the selected content.
  class Pruner
    CLUSTER_CONTAINERS = "ul, ol, menu, dl, div, section, p, td, li, span, table, header, footer"
    TEXT_BLOCKS = "p, div, span, li, h1, h2, h3, h4, h5, h6, small, section, aside, figcaption, b, strong, em, i"
    BYLINE = /byline|author|dateline|writtenby|p-author/.freeze
    SHARE = /(?<![a-z])(?:share|sharedaddy)(?![a-z])/.freeze
    # A class names a button when that is its last word, before a modifier,
    # a size or a rank: "btn", "c-button", "hero-cta", "btn--ghost",
    # "btn_medium", "button-primary". "button-text" and
    # "btn-view-author-options" name something else, and Bootstrap's
    # "btn-link" is a button that looks like a link.
    BUTTON_CLASS = /
      (?:\A|[-_])(?:btn|btns|button|buttons|cta|ctas)\d*
      (?:--[\w-]+|[-_](?:primary|secondary|tertiary|default|small|medium|large|sm|md|lg))?\z
    /x.freeze
    # Matched case-insensitively against the class and the id; no Unicode
    # letter folds to these, so it answers as downcasing first would.
    BUTTON_WORD = /btn|button|cta/i.freeze
    LINK_STYLED_BUTTON = /\A(?:btn|button)-link\z/.freeze
    # XPath finds a list of tags faster than CSS.
    CALL_TO_ACTION_HOLDERS = ".//a|.//span|.//div|.//p"
    # Tables not inside another table. Listing what is under every table
    # takes time that grows with the square of the number of tables.
    OUTER_TABLES = "descendant::table[not(ancestor::table)]"
    CARD_KEYS = 8
    CardLinks = Struct.new(:links, :keys, :read)
    CALL_TO_ACTION_PARTS = "img, picture, h1, h2, h3, h4, h5, h6, table, ul, ol, p"
    # A container conditional cleaning held out and put back: kept for the
    # panels it was kept with, it was gone when the share was read.
    HELD = "data-nokodown-held"
    # A node main removed and base kept, so it stays; gone when the share
    # or the fallback read the article as main did.
    SPARED = "data-nokodown-spared"
    LEFT_OUT = "[#{PostAttribution::OWN}], [#{HELD}], [#{SPARED}]"
    # Inside these a button is a title, a term or a footnote marker.
    LABEL_HOLDERS = %w[h1 h2 h3 h4 h5 h6 dt th sup label summary].freeze
    MIN_INDEX_LENGTH = 80
    DOWNLOAD = /\.(?:pdf|zip|docx?|xlsx?|pptx?|csv|epub|mp3|mp4|dmg|exe|msi|apk|tar|gz)\z/i.freeze

    def initialize(nodes, mode, conditional: true)
      @nodes = nodes
      @mode = mode
      @conditional = conditional
      @conditional_seen = 0
      @conditional_kept = 0
      @conditional_removed_links = 0
      @lines = {}
      @aside = {}
      @held = {}
      @spared = {}
    end

    def call
      @nodes.each do |root|
        @mode == :article ? prune_article(root) : prune_page(root)
        remove_boilerplate_text(root)
        remove_calls_to_action(root)
        release(taken(@lines), root)
      end
      self
    end

    # Share of the text conditional cleaning was given that it kept.
    def conditional_share
      @conditional_seen.zero? ? 1.0 : @conditional_kept.fdiv(@conditional_seen)
    end

    # Share of the text conditional cleaning removed that was link text.
    def removed_link_share
      removed = @conditional_seen - @conditional_kept
      removed.zero? ? 0.0 : @conditional_removed_links.fdiv(removed)
    end

    # The nodes' text without the poster's panels and lines, as it was
    # before PostAttribution read them.
    def self.length_without_own(nodes)
      pruner = new(nodes, :article)
      nodes.sum { |node| pruner.length_without_own(node) }
    end

    # No more than length_without_own: each of the poster's nodes (or a
    # held one) takes at most its text and the two spaces around it.
    def self.length_at_least(nodes)
      nodes.sum do |root|
        own = root.css(LEFT_OUT).sum { |node| Dom.text(node).length + 2 }
        Dom.text(root).length - own
      end
    end

    # The root's length as it was before the poster's panels became lines
    # (and without what was held out for them): what each container is
    # weighed against, and what the fallback reads as kept.
    def length_without_own(root)
      without_own(root) { Dom.text(root).length }
    end

    private

    # What the block answers with the poster's nodes (and what was held or
    # spared) out of the root, as main read it; all but what holds the node
    # kept.
    def without_own(root, kept = nil)
      own = {}
      keep = kept ? [kept, *kept.ancestors].select(&:element?).map { |node| Dom.key(node) }.to_set : Set.new
      root.css(LEFT_OUT).each do |node|
        hold(own, node) if below?(node, root) && !keep.include?(Dom.key(node))
      end
      yield
    ensure
      release(taken(own), root)
    end

    # What the block answers with the poster's lines set aside shown again
    # in the node, as base read it.
    def with_lines(node)
      shown = []
      unless @lines.empty?
        node.xpath("descendant::comment()").each do |place|
          line = @lines.fetch(Dom.key(place.parent), []).find { |_, held| held == place }
          next unless line

          place.add_previous_sibling(line.first)
          shown << line.first
        end
      end
      yield
    ensure
      shown&.each(&:unlink)
    end

    # The member panels a post's line stood for before PostAttribution read
    # them (PostAttribution::OWN), and the lines they left, were gone before
    # pruning then. The lines are set aside once the by-lines are removed,
    # until the root is pruned, and a panel left whole while conditional
    # cleaning runs: each step weighs and keeps what it did without them,
    # and each goes back where its place is still there. A comment holds
    # the place, as the page's own comments are gone. Grouped by the key of
    # what holds them.
    def set_aside(root, *values)
      selector = values.map { |value| "[#{PostAttribution::OWN}='#{value}']" }.join(", ")
      root.css(selector).each_with_object({}) do |node, aside|
        hold(aside, node) if below?(node, root)
      end
    end

    # Runs a rule as main read the post, with the poster's nodes of these
    # values held out, holding what the rule removes so each later check
    # sees it gone. Everything goes back; what was removed is returned, or
    # nil when none of the poster's nodes was there to hold out.
    def removed_without_own(root, *values)
      own = set_aside(root, *values)
      return if own.empty? && @lines.empty?

      gone = {}
      removed = []
      yield(lambda do |node|
        next if Dom.in_code?(node)

        removed << node
        hold(gone, node) if below?(node, root)
      end)
      removed.group_by { |node| Dom.key(node) }
    ensure
      release(taken(gone), root) if gone
      release(taken(own), root) if own
    end

    # Whether the node, or what holds it, was removed.
    def among?(removed, node)
      [node, *node.ancestors].any? { |held| held.element? && removed.fetch(Dom.key(held), []).include?(held) }
    end

    # What a store holds, in the order it was held (not grouped by what
    # holds it), leaving it empty.
    def taken(store)
      held = store.values.flatten(1).sort_by { |_, _, seq| seq }
      store.clear
      held
    end

    # Last held first, so what was held inside a later one is back in it.
    def release(held, root)
      held.reverse_each do |node, place, _|
        place.add_previous_sibling(node) if below?(place, root)
        place.unlink
      end
    end

    # What is set aside or held whose places are in the node.
    def aside_in(node)
      return [] if @lines.empty? && @aside.empty? && @held.empty? && @spared.empty?

      node.xpath("descendant::comment()").to_a.filter_map do |place|
        key = Dom.key(place.parent)
        [@lines, @aside, @held, @spared].flat_map { |store| store.fetch(key, []) }.find { |_, held| held == place }
      end
    end

    # Out of the root until it is put back, its place kept as a panel's is.
    def hold(store, node)
      place = node.document.create_comment("")
      node.add_previous_sibling(place)
      @seq = (@seq || 0) + 1
      (store[Dom.key(node.parent)] ||= []) << [node, place, @seq]
      node.unlink
    end

    def below?(node, root)
      key = Dom.key(root)
      node = node.parent
      node = node.parent while node&.element? && Dom.key(node) != key
      !node.nil? && node.element?
    end

    def prune_article(root)
      content_length = length_without_own(root)
      @raw_length = Dom.text(root).length
      remove_secondary(root, content_length)
      remove_bylines(root)
      # A second pass without conditional cleaning keeps the lines, as
      # their text tells a source's links from a cluster of them.
      @lines = set_aside(root, PostAttribution::OWN_LINE) if @conditional
      remove_article_furniture(root, content_length)
      remove_related_links(root)
      remove_stray_lines(root)
      clean_conditionally(root, content_length)
      root.css("h1, h2").each { |heading| remove(heading) if Scorer.cleaning_weight(heading).negative? }
    end

    def prune_page(root)
      remove_link_clusters(root)
    end

    # Boxes of links to other stories placed inside the body: "READ MORE:
    # <link>", a "More:" label over a list of headlines, a paragraph of links.
    # The panels' links were gone when main read a paragraph of links, and
    # there, with the lines they left, when base did: a box goes only if it
    # is one both ways.
    def remove_related_links(root)
      removed = removed_without_own(root, PostAttribution::OWN_PANEL) { |gone| related_links(root, gone) }
      return related_links(root, method(:remove)) unless removed
      return if removed.empty?

      with_lines(root) { related_links(root, ->(node) { remove(node) if among?(removed, node) }) }
      spare(removed, root)
    end

    # What main's view removed that is still there stays, spared.
    def spare(removed, root)
      removed.each_value { |nodes| nodes.each { |node| node[SPARED] = "" if below?(node, root) } }
    end

    def related_links(root, act)
      root.css("p, li, h2, h3, h4, h5, h6, strong, b").to_a.each do |node|
        text = Dom.text(node)
        if related_label?(text)
          with_link_box(node).each { |box| act.call(box) }
        elsif related_box?(node, text)
          act.call(node)
        end
      end
    end

    # "More:" or "DON'T MISS" on its own.
    def related_label?(text)
      text.length <= 30 && text.match?(Patterns::RELATED_LABEL) && text.sub(Patterns::RELATED_LABEL, "").empty?
    end

    # The label may sit in a wrapper of its own (Wikipedia's div.mw-heading),
    # so the box of links follows the wrapper.
    def with_link_box(label)
      text = Dom.text(label)
      holder = label
      holder = holder.parent while holder.next_element.nil? && holder.parent&.element? && Dom.text(holder.parent) == text
      following = holder.next_element
      following && link_density(following) >= 0.6 ? [following, holder] : [holder]
    end

    # "READ MORE: <headline>", or a paragraph made of several headlines. A
    # paragraph with no element in it holds no link, so it is not searched.
    def related_box?(node, text)
      return link_density(node) >= 0.5 if text.match?(Patterns::RELATED_LABEL)

      node.name == "p" && !node.first_element_child.nil? && node.css("a[href]").size >= 2 && link_density(node) >= 0.8
    end

    # Datelines and "follow us" lines; lines in a table stay. A block's text
    # is read only once it is known to be outside a table, or nested blocks
    # in a table would each read the same long text. Asking every block for
    # its table takes longer, so only blocks whose key is found in a table
    # are asked: misnested formatting copies a key elsewhere.
    def remove_stray_lines(root)
      nodes = root.css("p, div, span, li, small, time").to_a
      return if root.name == "table" || Dom.ancestors_named(root, "table").any?

      tabled = root.xpath(OUTER_TABLES).to_a.flat_map { |table| Dom.elements(table).map { |node| Dom.key(node) } }.to_set
      nodes.each do |node|
        next if tabled.include?(Dom.key(node)) && Dom.ancestors_named(node, "table").any?

        content = node.content
        next if Dom.squishes_longer?(content, 120)

        text = Dom.squish(content)
        remove(node) if text.length <= 120 && text.match?(Patterns::STRAY_LINE)
      end
    end

    def link_density(node)
      text_length = Dom.text(node).length
      return 0.0 if text_length.zero?

      link_text_length(node).fdiv(text_length)
    end

    def link_text_length(node)
      node.css("a[href]").to_a.sum { |link| Dom.text(link).length }
    end

    # Readability drops footers, asides and share widgets inside the article;
    # asides holding real prose (side notes) stay.
    # A footer or aside goes where it went as main read it (without the
    # poster's panels and lines) and as base did (with them); where only
    # main's view drops it, it stays, spared.
    def remove_article_furniture(root, content_length)
      root.css("footer").each do |node|
        furniture(root, node, content_length) { |total| Dom.text(node).length <= total * 0.5 }
      end
      root.css("aside").each do |node|
        furniture(root, node, content_length) { |total| Dom.text(node).length < 200 || ContainerCheck.new(node, total, Set.new).remove? }
      end
      Dom.elements(root).each do |node|
        next unless node.key?("class") || node.key?("id")

        remove(node) if Dom.signature(node).match?(SHARE) && Dom.text(node).length < 500
      end
    end

    # Main's view holds the poster's nodes, and what was spared before, out
    # of the post the node is in (all the checks read), or of the node; of
    # the root where the post holds it: the post is weighed without them.
    def furniture(root, node, content_length)
      post = node.ancestors.find { |ancestor| ancestor.element? && Dom.thread_post?(ancestor) }
      scope = post.nil? ? node : below?(post, root) ? post : root
      main = without_own(scope, node) { yield(content_length) }
      base = with_lines(node) { yield(@raw_length) }
      if main && base
        remove(node)
      elsif main
        node[SPARED] = ""
      end
    end

    # Turned off, it still drops unlabeled navigation, as page pruning does,
    # telling it without the poster's panels, as before they were read.
    def clean_conditionally(root, content_length)
      unless @conditional
        return remove_link_clusters(root)
      end

      @aside = set_aside(root, PostAttribution::OWN_PANEL)
      # What main's view removed and base's kept was gone when main
      # cleaned: it is out while the share is read, and put back after.
      root.css("[#{SPARED}]").each { |node| hold(@spared, node) if below?(node, root) }
      text_before = Dom.text(root).length
      links_before = link_text_length(root)
      remove_suspicious_containers(root, content_length)
      @conditional_seen += text_before
      @conditional_kept += Dom.text(root).length
      @conditional_removed_links += links_before - link_text_length(root)
      release(taken(@held), root)
      release(taken(@spared), root)
      release(taken(@aside), root)
    end

    # Innermost containers first, so an outer one is judged on what is left.
    def remove_suspicious_containers(root, content_length)
      paragraph_keys = Dom.paragraph_keys(root)
      memo = { root: root }
      ["form, fieldset", "table", "ul", "div"].each do |selector|
        root.css(selector).to_a.reverse_each do |node|
          next if paragraph_keys.include?(Dom.key(node)) || !ContainerCheck.new(node, content_length, paragraph_keys, memo).remove?

          ContainerCheck.forget(memo, node)
          if Dom.in_code?(node)
            next
          elsif kept_with_panels?(node, content_length, paragraph_keys)
            node[HELD] = ""
            hold(@held, node)
          else
            remove(node)
          end
        end
      end
    end

    # A container the check removes without the panels set aside, which it
    # kept with them before they were (a short post whose panel's line
    # outweighed its link, a reply named only by it), stays: held out while
    # the share is read, as it was gone then, and put back after. What a
    # held container shown again holds is shown too.
    def kept_with_panels?(node, content_length, paragraph_keys)
      shown = []
      loop do
        aside = aside_in(node).reject { |_, place| shown.any? { |_, seen| seen == place } }
        break if aside.empty?

        aside.each { |panel, place| place.add_previous_sibling(panel) }
        shown.concat(aside)
      end
      return false if shown.empty?

      !ContainerCheck.new(node, content_length, paragraph_keys, { root: node }).remove?
    ensure
      shown&.reverse_each { |panel, _| panel.unlink }
    end

    # A forum's thread is content.
    # Removing a node leaves its siblings in place, so the walk reads the next
    # one first.
    def remove_secondary(root, total)
      node = root.first_element_child
      while node
        following = node.next_element
        unless Dom.thread?(node)
          if Dom.secondary?(node) && Dom.text(node).length <= total * 0.5
            remove(node)
          else
            remove_secondary(node, total)
          end
        end
        node = following
      end
    end

    # The author line is returned as metadata, like Readability does. Many of
    # them mean a thread or a list of posts, where the authors are content.
    def remove_bylines(root)
      bylines = Dom.elements(root).select do |node|
        byline = node["rel"] == "author" || node["itemprop"].to_s.include?("author") || Dom.signature(node).match?(BYLINE)
        byline && Dom.text(node).length.between?(1, 99)
      end
      bylines.each { |node| remove(node) } if bylines.size <= 2
    end

    # Navigation that survived as unlabeled markup: several links, almost no
    # other text, and no link long enough to be a headline.
    # The poster's panels and lines were gone when main read the clusters,
    # and there when base did: a container goes only if it is one both ways.
    def remove_link_clusters(root)
      own = [PostAttribution::OWN_PANEL, PostAttribution::OWN_LINE]
      removed = removed_without_own(root, *own) { |gone| link_clusters(root, gone) }
      return link_clusters(root, method(:remove)) unless removed
      return if removed.empty?

      link_clusters(root, ->(node) { remove(node) if among?(removed, node) })
      spare(removed, root)
    end

    def link_clusters(root, act)
      clusters = root.css(CLUSTER_CONTAINERS).select { |node| link_cluster?(node) && !in_data_table?(node) }
      # Removal can only start at one of these, so none means nothing to remove.
      return if clusters.empty? || clusters_dominate?(root, clusters)

      root.css(CLUSTER_CONTAINERS).reverse_each do |node|
        act.call(node) if link_cluster?(node) && !in_data_table?(node)
      end
    end

    # On an index page (an A-Z list, a category grid) the clusters are the
    # content, not navigation around it. A footer sitemap, or a few skip and
    # account links left in a root that missed the content, is no index.
    # The root is weighed without the poster's lines, as before they were.
    def clusters_dominate?(root, clusters)
      index = outermost(clusters).reject do |node|
        %w[header footer].include?(node.name) || Dom.ancestors_named(node, "header", "footer").any?
      end
      length = index.sum { |node| Dom.text(node).length }
      length >= MIN_INDEX_LENGTH && length >= length_without_own(root) * 0.5
    end

    def outermost(nodes)
      keys = nodes.map { |node| Dom.key(node) }.to_set
      nodes.reject do |node|
        node.ancestors.any? { |ancestor| ancestor.element? && keys.include?(Dom.key(ancestor)) }
      end
    end

    def link_cluster?(node)
      links = node.css("a[href]")
      return false if links.size < 3

      text_length = Dom.text(node).length
      lengths = links.map { |link| Dom.text(link).length }
      text_length.positive? && lengths.max < 30 && lengths.sum.fdiv(text_length) >= 0.7
    end

    def in_data_table?(node)
      tables = node.name == "table" ? [node] : []
      (tables + Dom.ancestors_named(node, "table")).any? { |table| Tables.data_table?(table) }
    end

    def remove_boilerplate_text(root)
      root.css(TEXT_BLOCKS).to_a.each do |node|
        content = node.content
        next if Dom.squishes_longer?(content, 200)

        text = Dom.squish(content)
        next if text.empty? || text.length > 200

        boilerplate = text.length <= 80 && text.match?(Patterns::BOILERPLATE_TEXT)
        copyright = Patterns.copyright?(text) && node.at_css("img").nil?
        remove(node) if boilerplate || copyright
      end
    end

    # Links and boxes styled as buttons ("Add to cart", "Book a demo") are
    # controls, not content. Cards (an image, a heading, a list) are content.
    # All are judged before any is removed, so the order XPath returns them in
    # does not matter.
    def remove_calls_to_action(root)
      @running_text = {}
      @text_lengths = {}
      @card_links = {}
      root.xpath(CALL_TO_ACTION_HOLDERS).to_a.select { |node| call_to_action?(node) }.each { |node| remove(node) }
    end

    def destination(link)
      href = UrlResolver.normalize(link["href"])
      href unless href.empty? || href.start_with?("#") || UrlResolver.script?(href)
    end

    def links_of(node)
      (node.name == "a" ? [node] : node.css("a[href]").to_a).select { |link| destination(link) }
    end

    def download?(node)
      links_of(node).any? { |link| destination(link).sub(/[?#].*/m, "").match?(DOWNLOAD) }
    end

    def only_link_in_card?(node, card)
      own = links_of(node).map { |link| Dom.key(link) }
      return false if own.empty? || card.nil?

      card = card_links(card)
      return false unless card.keys.all? { |key| own.include?(key) }

      links = card.links
      while card.read < links.size && card.keys.size <= CARD_KEYS
        link = links[card.read]
        card.read += 1
        next unless destination(link)

        key = Dom.key(link)
        next if card.keys.include?(key)

        card.keys << key
        return false unless own.include?(key)
      end
      return true if card.keys.size <= CARD_KEYS

      (card.read...links.size).none? { |index| destination(links[index]) && !own.include?(Dom.key(links[index])) }
    end

    # A card's links, kept as the node set the query returns so nested cards
    # hold no node objects, and the distinct keys of those that lead
    # elsewhere, read in order only as far as some control has needed and no
    # further than CARD_KEYS + 1 keys. A control lacking one of these keys is
    # not the card's only link; one holding them all goes on from where the
    # reading stopped, as a direct scan would, without reading a link twice.
    def card_links(card)
      known(@card_links, card) { CardLinks.new(card.css("a[href]"), [], 0) }
    end

    def call_to_action?(node)
      return false unless button?(node)

      text = Dom.text(node)
      return false if text.length > 40 || text.split.size > 6 || text.match?(/\d/) || node.at_css(CALL_TO_ACTION_PARTS)
      return false if Dom.ancestors_named(node, *LABEL_HOLDERS).any?

      # FAQ questions and section titles that open a disclosure; the toggle
      # may be a wrapper around the styled label.
      wrappers = wrappers(node, text)
      return false if text.end_with?("?") || wrappers.any? { |wrapper| toggle?(wrapper) }
      return false if download?(node) || only_link_in_card?(node, wrappers.last.parent)

      # In a data table the button is a cell value, like a plan's "Order" column.
      !inside_sentence?(wrappers) && !in_data_table?(node)
    end

    def button?(node)
      return true if node["role"] == "button"
      return false unless node["class"]&.match?(BUTTON_WORD) || node["id"]&.match?(BUTTON_WORD)

      tokens = Dom.signature(node).split
      tokens.any? { |token| token.match?(BUTTON_CLASS) } && tokens.none? { |token| token.match?(LINK_STYLED_BUTTON) }
    end

    # The node and the elements around it that hold nothing else, such as the
    # link of an accordion title around a styled label.
    def wrappers(node, text)
      chain = [node]
      parent = node.parent
      while parent&.element? && text_length(parent) == text.length && Dom.text(parent) == text
        chain << parent
        parent = parent.parent
      end
      chain
    end

    def text_length(node)
      known(@text_lengths, node) { Dom.text(node).length }
    end

    # Buttons are judged before any is removed, so what is read about the
    # elements around them holds for all of them: a page can put thousands
    # of buttons in one element. Kept by key and checked by node, as copies
    # of a misnested element share a key.
    def known(store, node)
      key = Dom.key(node)
      return yield unless key

      entry = store[key]
      return entry[1] if entry && entry[0] == node

      yield.tap { |value| store[key] = [node, value] }
    end

    def toggle?(node)
      node.key?("aria-expanded") || node.key?("aria-controls") || Dom.signature(node).match?(Patterns::DISCLOSURE)
    end

    # A button-styled link in running text ("<a class=btn>Download</a> the
    # installer") is part of the sentence. Blocks and other buttons beside it
    # are not running text, so a button after a heading or in a group is not.
    def inside_sentence?(wrappers)
      control = wrappers.last
      return false if control.parent.nil? || wrappers.any? { |wrapper| Dom.block?(wrapper) }

      running_text(control.parent) - running_text_length(control) >= 20
    end

    def running_text(parent)
      @running_text[Dom.key(parent)] ||= parent.children.sum { |child| running_text_length(child) }
    end

    def running_text_length(child)
      return Dom.text(child).length if child.text?
      return 0 if !child.element? || Dom.block?(child) || button?(child)

      Dom.text(child).length
    end

    # Every rule removes through here: nothing inside code is furniture.
    def remove(node)
      node.remove unless Dom.in_code?(node)
    end
  end
end

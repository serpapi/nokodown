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
    BUTTON_WORD = /btn|button|cta/.freeze
    LINK_STYLED_BUTTON = /\A(?:btn|button)-link\z/.freeze
    CALL_TO_ACTION_PARTS = "img, picture, h1, h2, h3, h4, h5, h6, table, ul, ol, p"
    HEADINGS = "h1, h2, h3, h4, h5, h6"
    # Inside these a button is a title, a term or a footnote marker.
    LABEL_HOLDERS = %w[h1 h2 h3 h4 h5 h6 dt th sup label summary].freeze
    MIN_INDEX_LENGTH = 80
    # A counter or label a script never filled in: "{{options.likeCount}}".
    UNRENDERED_TEMPLATE = /\A(?:\{\{[^{}]*\}\}\s*)+\z/.freeze
    DOWNLOAD = /\.(?:pdf|zip|docx?|xlsx?|pptx?|csv|epub|mp3|mp4|dmg|exe|msi|apk|tar|gz)\z/i.freeze

    def initialize(nodes, mode, conditional: true)
      @nodes = nodes
      @mode = mode
      @conditional = conditional
      @conditional_seen = 0
      @conditional_kept = 0
      @conditional_removed_links = 0
    end

    def call
      @nodes.each do |root|
        @mode == :article ? prune_article(root) : remove_link_clusters(root)
        remove_boilerplate_text(root)
        remove_calls_to_action(root)
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

    private

    def prune_article(root)
      content_length = Dom.text(root).length
      remove_secondary(root, content_length)
      remove_bylines(root)
      remove_article_furniture(root, content_length)
      remove_related_links(root)
      remove_stray_lines(root)
      clean_conditionally(root, content_length)
      root.css("h1, h2").each { |heading| remove(heading) if Scorer.cleaning_weight(heading).negative? }
    end

    # Boxes of links to other stories placed inside the body: "READ MORE:
    # <link>", a "More:" label over a list of headlines, a paragraph of links.
    def remove_related_links(root)
      root.css("p, li, h2, h3, h4, h5, h6, strong, b").each do |node|
        text = Dom.text(node)
        if related_label?(text)
          remove_with_link_box(node)
        elsif related_box?(node, text)
          remove(node)
        end
      end
    end

    # "More:" or "DON'T MISS" on its own.
    def related_label?(text)
      text.length <= 30 && text.match?(Patterns::RELATED_LABEL) && text.sub(Patterns::RELATED_LABEL, "").empty?
    end

    # The label may sit in a wrapper of its own (Wikipedia's div.mw-heading),
    # so the box of links follows the wrapper.
    def remove_with_link_box(label)
      text = Dom.text(label)
      holder = label
      holder = holder.parent while holder.next_element.nil? && holder.parent&.element? && Dom.text(holder.parent) == text
      following = holder.next_element
      remove(following) if following && link_density(following) >= 0.6
      remove(holder)
    end

    # "READ MORE: <headline>", or a paragraph made of several headlines.
    def related_box?(node, text)
      return link_density(node) >= 0.5 if text.match?(Patterns::RELATED_LABEL)

      node.name == "p" && node.css("a[href]").size >= 2 && link_density(node) >= 0.8
    end

    # Datelines and "follow us" lines.
    def remove_stray_lines(root)
      root.css("p, div, span, li, small, time").each do |node|
        next if Dom.ancestors_named(node, "table").any?

        text = Dom.text(node)
        remove(node) if text.length <= 120 && text.match?(Patterns::STRAY_LINE)
      end
    end

    def link_density(node)
      text_length = Dom.text(node).length
      return 0.0 if text_length.zero?

      link_text_length(node).fdiv(text_length)
    end

    def link_text_length(node)
      node.css("a[href]").sum { |link| Dom.text(link).length }
    end

    # Readability drops footers, asides and share widgets inside the article;
    # asides holding real prose (side notes) stay.
    def remove_article_furniture(root, content_length)
      root.css("footer").each { |node| remove(node) if Dom.text(node).length <= content_length * 0.5 }
      root.css("aside").each do |node|
        remove(node) if Dom.text(node).length < 200 || ContainerCheck.new(node, content_length, Set.new).remove?
      end
      root.css("[class], [id]").each do |node|
        remove(node) if Dom.signature(node).match?(SHARE) && Dom.text(node).length < 500
      end
    end

    # Turned off, it still drops unlabeled navigation, as page pruning does.
    def clean_conditionally(root, content_length)
      return remove_link_clusters(root) unless @conditional

      text_before = Dom.text(root).length
      links_before = link_text_length(root)
      remove_suspicious_containers(root, content_length)
      @conditional_seen += text_before
      @conditional_kept += Dom.text(root).length
      @conditional_removed_links += links_before - link_text_length(root)
    end

    # Innermost containers first, so an outer one is judged on what is left.
    def remove_suspicious_containers(root, content_length)
      paragraph_keys = Dom.paragraph_keys(root)
      memo = { root: root }
      ["form, fieldset", "table", "ul", "div"].each do |selector|
        root.css(selector).reverse_each do |node|
          next if paragraph_keys.include?(Dom.key(node)) || !ContainerCheck.new(node, content_length, paragraph_keys, memo).remove?

          ContainerCheck.forget(memo, node)
          remove(node)
        end
      end
    end

    # A forum's thread is content.
    def remove_secondary(root, total)
      root.element_children.each do |node|
        next if Dom.thread?(node)

        if Dom.signature(node).match?(Patterns::SECONDARY) && Dom.text(node).length <= total * 0.5
          remove(node)
        else
          remove_secondary(node, total)
        end
      end
    end

    # The author line is returned as metadata, like Readability does. Many of
    # them mean a thread or a list of posts, where the authors are content.
    def remove_bylines(root)
      bylines = root.css("*").select do |node|
        byline = node["rel"] == "author" || node["itemprop"].to_s.include?("author") || Dom.signature(node).match?(BYLINE)
        byline && Dom.text(node).length.between?(1, 99)
      end
      bylines.each { |node| remove(node) } if bylines.size <= 2
    end

    # Navigation that survived as unlabeled markup: several links, almost no
    # other text, and no link long enough to be a headline.
    def remove_link_clusters(root)
      clusters = root.css(CLUSTER_CONTAINERS).select { |node| link_cluster?(node) && !in_data_table?(node) }
      # Removal can only start at one of these, so none means nothing to remove.
      return if clusters.empty? || clusters_dominate?(root, clusters)

      root.css(CLUSTER_CONTAINERS).reverse_each do |node|
        remove(node) if link_cluster?(node) && !in_data_table?(node) && !teaser_header?(node)
      end
    end

    # One linked heading with its date and author links heads a teaser, not
    # a menu, however short the title: in Chinese or Japanese it fits in a
    # dozen characters. Menus of linked headings have several.
    def teaser_header?(node)
      node.css("a[href]").count { |link| headline?(link) } == 1
    end

    def headline?(link)
      Dom.ancestors_named(link, *Dom::HEADINGS).any? || !link.at_css(HEADINGS).nil?
    end

    # On an index page (an A-Z list, a category grid) the clusters are the
    # content, not navigation around it. A footer sitemap, or a few skip and
    # account links left in a root that missed the content, is no index.
    def clusters_dominate?(root, clusters)
      index = outermost(clusters).reject do |node|
        %w[header footer].include?(node.name) || Dom.ancestors_named(node, "header", "footer").any?
      end
      length = index.sum { |node| Dom.text(node).length }
      length >= MIN_INDEX_LENGTH && length >= Dom.text(root).length * 0.5
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
      root.css(TEXT_BLOCKS).each do |node|
        text = Dom.text(node)
        next if text.empty? || text.length > 200

        boilerplate = text.length <= 80 && text.match?(Patterns::BOILERPLATE_TEXT)
        copyright = text.match?(Patterns::COPYRIGHT_TEXT) && node.at_css("img").nil?
        remove(node) if boilerplate || copyright || text.match?(UNRENDERED_TEMPLATE)
      end
    end

    # Links and boxes styled as buttons ("Add to cart", "Book a demo") are
    # controls, not content. Cards (an image, a heading, a list) are content.
    # All are judged before any is removed, so document order does not matter.
    def remove_calls_to_action(root)
      @running_text = {}
      root.css("a, span, div, p").select { |node| call_to_action?(node) }.each { |node| remove(node) }
    end

    def destination(link)
      href = link["href"].to_s.strip
      href unless href.empty? || href.start_with?("#") || href.match?(/\Ajavascript:/i)
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

      card.css("a[href]").none? { |link| destination(link) && !own.include?(Dom.key(link)) }
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
      return false unless "#{node["class"]} #{node["id"]}".downcase.match?(BUTTON_WORD)

      tokens = Dom.signature(node).split
      tokens.any? { |token| token.match?(BUTTON_CLASS) } && tokens.none? { |token| token.match?(LINK_STYLED_BUTTON) }
    end

    # The node and the elements around it that hold nothing else, such as the
    # link of an accordion title around a styled label.
    def wrappers(node, text)
      chain = [node]
      parent = node.parent
      while parent&.element? && Dom.text(parent) == text
        chain << parent
        parent = parent.parent
      end
      chain
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

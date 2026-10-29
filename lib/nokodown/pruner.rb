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
    # Inside these a button is a title, a term or a footnote marker.
    LABEL_HOLDERS = %w[h1 h2 h3 h4 h5 h6 dt th sup label summary].freeze
    MIN_INDEX_LENGTH = 80
    MIN_TITLED_CONTENT = 200
    MIN_LEFT = 200
    MIN_PROSE_COLUMN = 100
    SECTION_HEADINGS = %w[h2 h3 h4 h5 h6].freeze
    SECTION_HEADING_SELECTOR = SECTION_HEADINGS.join(", ")
    LETTER = /\p{L}/.freeze
    DOWNLOAD = /\.(?:pdf|zip|docx?|xlsx?|pptx?|csv|epub|mp3|mp4|dmg|exe|msi|apk|tar|gz)\z/i.freeze

    def initialize(nodes, mode, conditional: true, urls: nil)
      @nodes = nodes
      @mode = mode
      @conditional = conditional
      @urls = urls
      @conditional_seen = 0
      @conditional_kept = 0
      @conditional_removed_links = 0
    end

    def call
      @nodes.each do |root|
        @mode == :article ? prune_article(root) : prune_page(root)
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

    def prune_page(root)
      remove_rail_columns(root)
      remove_link_clusters(root)
    end

    # Pages laid out in table columns put the site's menu or a rail of other
    # stories in a column of links beside the column of prose.
    def remove_rail_columns(root)
      root.css("tr").each do |row|
        cells = Tables.cells(row)
        next if cells.size < 2 || cells.none? { |cell| prose_column?(cell) } || in_data_table?(row)

        cells.each { |cell| remove(cell) if rail_column?(cell) }
      end
    end

    def prose_column?(cell)
      Dom.text(cell).length >= MIN_PROSE_COLUMN && link_density(cell) < 0.3
    end

    # Preformatted listings link each of their entries too.
    def rail_column?(cell)
      cell.css("a[href]").size >= 3 && link_density(cell) >= 0.6 && !cell.at_css("pre")
    end

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
    # other text, and no link long enough to be a headline. An index page
    # keeps its clusters, which are its content, but not its menus.
    def remove_link_clusters(root)
      clusters = link_clusters(root)
      index = !clusters.empty? && clusters_dominate?(root, clusters)
      remove_menus(root, index ? clusters_above_title(root, clusters) : [])
      # Removal can only start at a cluster, so none means nothing to remove.
      return if index || clusters.empty?

      root.css(CLUSTER_CONTAINERS).reverse_each do |node|
        remove_with_label(node, root) if link_cluster?(node) && !in_data_table?(node)
      end
    end

    # Menus stay when they are nearly all the page holds.
    def remove_menus(root, menus)
      menus = outermost((menus + current_page_menus(root)).uniq { |menu| Dom.key(menu) })
      return if menus.empty? || Dom.text(root).length - menus.sum { |menu| Dom.text(menu).length } < MIN_LEFT

      menus.each { |menu| remove_with_label(menu, root) }
    end

    def link_clusters(root)
      root.css(CLUSTER_CONTAINERS).select { |node| link_cluster?(node) && !in_data_table?(node) }
    end

    # The page title opens the content, so the clusters before it are the
    # site's menus. A title with little after it, like an SEO line at the
    # foot of the page, opens nothing.
    def clusters_above_title(root, clusters)
      title = root.at_css("h1")
      return [] if title.nil? || text_after(title, root) < MIN_TITLED_CONTENT

      position = Dom.key(title).to_i
      outermost(clusters).select { |node| Dom.key(node).to_i < position && !node.at_css("h1") }
    end

    def text_after(node, root)
      length = 0
      until node.nil? || Dom.key(node) == Dom.key(root)
        sibling = node
        length += Dom.text(sibling).length while (sibling = sibling.next_sibling)
        node = node.parent
      end
      length
    end

    # A list of links holding one to the page itself shows the reader where
    # they are: a menu, a breadcrumb trail, a pager.
    def current_page_menus(root)
      return [] unless @urls

      links = root.css("a[href]").select { |link| @urls.current_page?(link["href"]) }
      links.filter_map { |link| menu_of(link, root) }
    end

    def menu_of(link, root)
      holder = link.ancestors.find { |ancestor| !ancestor.element? || ancestor.css("a[href]").size >= 3 }
      holder if holder&.element? && inside?(holder, root) && menu_entries?(holder) && !in_data_table?(holder)
    end

    # Alike entries of one link each, perhaps with a count beside it, and
    # separators between them. Cards that link to their title, category and
    # author, or a post header whose title links to itself, are no menu.
    def menu_entries?(holder)
      entries, rest = holder.element_children.partition { |child| child.name == "a" || child.at_css("a[href]") }
      entries.size >= 3 && entries.map(&:name).uniq.size == 1 && entries.all? { |entry| one_link?(entry) } &&
        rest.none? { |child| Dom.text(child).match?(LETTER) }
    end

    # A gallery's thumbnails link to each picture without a word.
    def one_link?(entry)
      links = entry.name == "a" ? [entry] : entry.css("a[href]")
      return false unless links.size == 1

      label = Dom.text(links.first)
      !label.empty? && !Dom.text(entry).sub(label, "").match?(LETTER)
    end

    def inside?(node, root)
      key = Dom.key(root)
      node&.element? && node.ancestors.any? { |ancestor| ancestor.element? && Dom.key(ancestor) == key }
    end

    def remove_with_label(node, root)
      labels = labels_of(node, root)
      remove(node)
      labels.each { |label| remove(label) }
    end

    # The headings over a box of links label nothing once the box is gone,
    # unless more of their section follows. Widgets nest the box and its
    # heading in wrappers, each level with a heading of its own.
    def labels_of(node, root)
      labels = []
      holder = node
      loop do
        holder = holder.parent while only_child?(holder) && inside?(holder.parent, root)
        label = holder.previous_element
        break unless label && section_label?(label) && section_end?(holder)

        labels << label
        break unless label.previous_element.nil? && holder.next_element.nil? && inside?(holder.parent, root)

        holder = holder.parent
      end
      labels
    end

    def only_child?(node)
      node.previous_element.nil? && node.next_element.nil?
    end

    def section_end?(node)
      node.next_element.nil? || section_label?(node.next_element)
    end

    # A heading below the page title, or a wrapper holding only one. A linked
    # heading is the title of a card, not a label.
    def section_label?(node)
      text = Dom.text(node)
      return false if text.empty? || node.at_css("a[href]")
      return true if SECTION_HEADINGS.include?(node.name)

      node.css(SECTION_HEADING_SELECTOR).any? { |heading| Dom.text(heading) == text }
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
        remove(node) if boilerplate || copyright
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

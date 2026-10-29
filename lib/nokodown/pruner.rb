# frozen_string_literal: true

module Nokodown
  # Final cleanup inside the selected content.
  class Pruner
    CLUSTER_CONTAINERS = "ul, ol, menu, dl, div, section, p, td, li, span, table, header, footer"
    TEXT_BLOCKS = "p, div, span, li, h1, h2, h3, h4, h5, h6, small, section, aside, figcaption, b, strong, em, i"
    LAYOUT_CELLS = "td, center, font"
    NOTICE_BLOCKS = "#{TEXT_BLOCKS}, #{LAYOUT_CELLS}"
    MAX_NOTICE = 200
    NO_WORDS = /\A[\p{P}\p{S}\p{N}\s]*\z/.freeze
    BYLINE = /byline|author|dateline|writtenby|p-author/.freeze
    SHARE = /(?<![a-z])(?:share|sharedaddy)(?![a-z])/.freeze
    # A class names a button when that is its last word, before a modifier,
    # a size, a rank or a color: "btn", "c-button", "hero-cta", "btn--ghost",
    # "btn_medium", "button-primary", "btn-outline-dark". "button-text" and
    # "btn-view-author-options" name something else, and Bootstrap's
    # "btn-link" is a button that looks like a link.
    BUTTON_CLASS = /
      (?:\A|[-_])(?:btn|btns|button|buttons|cta|ctas)\d*
      (?:--[\w-]+|[-_](?:primary|secondary|tertiary|default|small|medium|large|xs|sm|md|lg|xl|
      light|dark|white|black|success|danger|warning|info|ghost|solid|block|outline(?:-[a-z]+)?))?\z
    /x.freeze
    # Component libraries (shadcn/ui and others) name the part an element plays.
    BUTTON_PART = %w[data-slot data-component data-part].freeze
    BUTTON_WORD = /btn|button|cta/.freeze
    LINK_STYLED_BUTTON = /\A(?:btn|button)-link\z/.freeze
    CALL_TO_ACTION_PARTS = "img, picture, h1, h2, h3, h4, h5, h6, table, ul, ol, p"
    # Inside these a button is a title, a term or a footnote marker.
    LABEL_HOLDERS = %w[h1 h2 h3 h4 h5 h6 dt th sup label summary].freeze
    MIN_INDEX_LENGTH = 80
    MIN_TITLED_CONTENT = 200
    MIN_LEFT = 200
    SENTENCE_TEXT = 20
    MIN_PROSE_COLUMN = 100
    GRID_CLASS = /\A(?:span|td-pb-span|col-(?:(xs|sm|md|lg|xl|xxl)-)?|(small|medium|large)-)(\d{1,2})\z/.freeze
    BREAKPOINTS = [nil, "xs", "sm", "md", "lg", "xl", "xxl"].freeze
    FOUNDATION = { "small" => "sm", "medium" => "md", "large" => "lg" }.freeze
    SIDE_CELL = /\A(?:side-border-(?:left|right)|left-side|right-side)\z/.freeze
    GRID_COLUMNS = "[class*=span], [class*=col-], [class*=large-], [class*=medium-], [class*=small-], [class*=side]"
    SIDE_WIDTH = 3
    FULL_WIDTH = 12
    NOT_COLUMNS = %w[style script noscript template link meta].freeze
    MIN_MAIN_WIDTH = 7
    MAX_RAIL_WIDTH = 5
    RAIL_LINK_SHARE = 0.5
    WIDTH = /\A\s*(\d+(?:\.\d+)?)\s*(%|px)?\s*\z/i.freeze
    STYLE_WIDTH = /(?:\A|;)\s*width\s*:\s*([^;]+)/i.freeze
    MAX_LABEL = 40
    HEADLINE_WIDTH = 30
    SECTION_HEADINGS = %w[h2 h3 h4 h5 h6].freeze
    SECTION_HEADING_SELECTOR = SECTION_HEADINGS.join(", ").freeze
    MIN_SERIES = 3
    MEDIA = %w[img picture iframe].freeze
    MEDIA_SELECTOR = MEDIA.join(", ")
    # A CJK character says about as much as a short word.
    WIDE = /[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}]/.freeze
    # One colon, at the end: "Tag: Ants Show: Sort:" is a header with controls.
    LEAD = /\A[^:：]+[:：]\z/.freeze
    LETTER = /\p{L}/.freeze
    # What may follow a site footer: a copyright line, a back-to-top link.
    TAIL_SHARE = 0.1
    TAIL_CHARS = 100
    # On a page with little text, such as a gallery of images, where a
    # footer sits tells nothing.
    MIN_TAIL_TEXT = 200
    # A footer holding most of the content is the content.
    MAX_TAIL_SHARE = 0.5
    QUOTES = %w[blockquote figure].freeze
    SECTIONS = %w[section aside nav].freeze
    DOWNLOAD = /\.(?:pdf|zip|docx?|xlsx?|pptx?|csv|epub|mp3|mp4|dmg|exe|msi|apk|tar|gz)\z/i.freeze

    def initialize(nodes, mode, conditional: true, urls: nil)
      @nodes = nodes
      @mode = mode
      @conditional = conditional
      @urls = urls
      @conditional_seen = 0
      @conditional_kept = 0
      @conditional_removed_links = 0
      @data_tables = {}
    end

    def call
      @nodes.each do |root|
        # Before the index decision, which a long pager would sway.
        Pagers.find(root).each { |node| remove_with_label(node, root, Set.new) }
        remove_in_page_links(root)
        @mode == :article ? prune_article(root) : prune_page(root)
        remove_boilerplate_text(root)
        remove_calls_to_action(root)
        ReadMoreLinks.new(root).call
      end
      # Article cleaning works on copies cut from the page, which cannot tell
      # whether the main landmark holds a footer.
      remove_tail_footers if @mode == :page
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

    def remove_in_page_links(root)
      @anchors ||= InPageLinks.anchors(root.document)
      links = InPageLinks.new(root, @anchors, @urls)
      links.contents.each { |node| remove_with_label(node, root, Set.new) }
      links.back_links.each { |link| remove(link) }
    end

    # A page whose side columns made it look like an index is judged again
    # without them, but no page becomes an index by losing them.
    def prune_page(root)
      clusters = link_clusters(root)
      index = index?(root, clusters)
      if remove_rail_columns(root, index)
        clusters = link_clusters(root)
        index &&= index?(root, clusters)
      end
      remove_link_clusters(root, clusters, index)
    end

    # Pages laid out in table columns put the site's menu or a rail of other
    # stories in a column of links beside the column of prose. Says whether
    # any went.
    def remove_rail_columns(root, index)
      rails = outermost(root.css("tr").flat_map { |row| rails_of(row, index) } + grid_rails(root))
      return false if rails.empty? || Dom.text(root).length - rails.sum { |cell| Dom.text(cell).length } < MIN_LEFT

      rails.each { |cell| remove(cell) }
      true
    end

    def rails_of(row, index)
      cells = Tables.cells(row)
      return [] if cells.size < 2

      prose = cells.select { |cell| prose_column?(cell) }
      return [] if prose.empty? || in_data_table?(row)

      cells.select { |cell| rail_column?(cell) && side_column?(cell, prose, cells, index) }
    end

    # Grid frameworks give columns their width in twelfths ("col-md-4" beside
    # "col-md-8", "td-pb-span4"), and old portals name their side cells. A
    # side column of links goes beside the widest column; one with little
    # link text, such as a price box or
    # an event's date and place, stays. Beside side-named cells, the other
    # cell is the main one.
    def grid_rails(root)
      parents = root.css(GRID_COLUMNS).map(&:parent).uniq { |parent| Dom.key(parent) }
      parents.flat_map { |parent| side_rails(parent.element_children.to_a) }
    end

    def side_rails(children)
      columns = children.reject { |child| NOT_COLUMNS.include?(child.name) }
      return [] unless columns.size.between?(2, 3)

      side_row = columns.any? { |column| side_cell?(column) }
      widths = columns.map { |column| side_row ? (side_cell?(column) ? SIDE_WIDTH : FULL_WIDTH) : grid_width(column) }
      return [] if widths.include?(nil)

      main = widths.index(widths.max)
      return [] unless widths[main] >= MIN_MAIN_WIDTH && main_column?(columns[main], columns)

      columns.each_index.select { |index| index != main && rail?(columns[index], widths[index]) }.map { |index| columns[index] }
    end

    # The title's column, or else a column of prose: beside a hub's main
    # list of links, the narrow lists are more of the hub.
    def main_column?(column, columns)
      return !column.at_css("h1").nil? if columns.any? { |other| other.at_css("h1") }

      link_density(column) < RAIL_LINK_SHARE
    end

    def rail?(column, width)
      width <= MAX_RAIL_WIDTH && column.at_css("h1").nil? && link_density(column) >= RAIL_LINK_SHARE
    end

    def side_cell?(column)
      column["class"].to_s.split.any? { |name| name.match?(SIDE_CELL) }
    end

    # Twelfths, from the widest breakpoint a class names.
    def grid_width(column)
      widths = column["class"].to_s.split.filter_map do |name|
        match = name.match(GRID_CLASS)
        [BREAKPOINTS.index(match[1] || FOUNDATION[match[2]]), match[3].to_i] if match
      end
      widths.max_by(&:first)&.last
    end

    # The widths a table declares tell a side column from the main one, which
    # may be a listing beside a short contact or intro column. An index page
    # only loses a column declared narrower, and the title is never on a side.
    def side_column?(cell, prose, cells, index)
      return false if cell.at_css("h1")
      return prose.any? { |column| narrower?(cell, column, cells) } if index

      prose.none? { |column| narrower?(column, cell, cells) }
    end

    # Declared narrower in the same unit, or beside a column that declares no
    # width while the rest of the row does, as that one takes what is left.
    def narrower?(column, other, cells)
      width = column_width(column)
      other_width = column_width(other)
      return width.last == other_width.last && width.first < other_width.first if width && other_width

      other_width.nil? && cells.all? { |cell| Dom.key(cell) == Dom.key(other) || column_width(cell)&.last == "px" }
    end

    def column_width(cell)
      match = (cell["width"] || cell["style"].to_s[STYLE_WIDTH, 1]).to_s.match(WIDTH)
      [match[1].to_f, match[2] == "%" ? "%" : "px"] if match
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
      unless @conditional
        clusters = link_clusters(root)
        return remove_link_clusters(root, clusters, index?(root, clusters))
      end

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
    #
    # Elsewhere menus go after the clusters, so a menu does not split the
    # cluster around it ("Posted in News | Tagged a, b | Comment") and leave
    # pieces of it behind, and the list a submenu hung from is judged again.
    def remove_link_clusters(root, clusters, index)
      return remove_menus(root, clusters_above_title(root, clusters) + current_page_menus(root)) if index

      # Removal can only start at a cluster, so none means nothing to remove.
      repeated = repeated_shapes(clusters)
      remove_clusters(root, repeated) unless clusters.empty?
      remove_clusters(root, repeated) if remove_menus(root, current_page_menus(root))
    end

    def index?(root, clusters)
      !clusters.empty? && clusters_dominate?(root, clusters)
    end

    def remove_clusters(root, repeated)
      root.css(CLUSTER_CONTAINERS).reverse_each do |node|
        remove_with_label(node, root, repeated) if link_cluster?(node) && !in_data_table?(node)
      end
    end

    # Menus stay when they are nearly all the page holds. Says whether any went.
    def remove_menus(root, menus)
      menus = outermost(menus.uniq { |menu| Dom.key(menu) })
      return false if menus.empty? || Dom.text(root).length - menus.sum { |menu| Dom.text(menu).length } < MIN_LEFT

      repeated = repeated_shapes(menus)
      menus.each { |menu| remove_with_label(menu, root, repeated) }
      true
    end

    def link_clusters(root)
      root.css(CLUSTER_CONTAINERS).select { |node| link_cluster?(node) && !in_data_table?(node) }
    end

    # The page title opens the content, so the clusters before it are the
    # site's menus. A title with little after it, like an SEO line at the
    # foot of the page, opens nothing. Keys number elements in document
    # order, so a lower key comes first.
    def clusters_above_title(root, clusters)
      title = root.at_css("h1")
      return [] if title.nil? || Dom.key(title).nil? || text_length_after(title, root) < MIN_TITLED_CONTENT

      position = Dom.key(title).to_i
      outermost(clusters).select do |node|
        Dom.key(node) && Dom.key(node).to_i < position && !node.at_css("h1") && !headlines?(node)
      end
    end

    # A cluster's links are short in characters, but a CJK headline of
    # fifteen characters reads as long as one in English, and a list of
    # them is a listing, not a menu.
    def headlines?(node)
      node.css("a[href]").any? { |link| label_length(Dom.text(link)) >= HEADLINE_WIDTH }
    end

    def text_length_after(node, root)
      length = 0
      until node.nil? || Dom.key(node) == Dom.key(root)
        sibling = node
        length += Dom.text(sibling).length while (sibling = sibling.next_sibling)
        node = node.parent
      end
      length
    end

    # A list of links holding one to the page itself shows the reader where
    # they are: a menu, a breadcrumb trail, a pager. Links in one list share
    # a holder, which is judged once.
    def current_page_menus(root)
      return [] unless @urls

      link_counts = {}
      holders = root.css("a[href]").filter_map do |link|
        link_holder(link, root, link_counts) if @urls.current_page?(link["href"])
      end
      holders.uniq { |holder| Dom.key(holder) }.select { |holder| !in_data_table?(holder) && menu_entries?(holder) }
    end

    # The nearest ancestor below the root that holds three links or more.
    def link_holder(link, root, link_counts)
      root_key = Dom.key(root)
      link.ancestors.each do |ancestor|
        return unless ancestor.element?

        key = Dom.key(ancestor)
        return if key == root_key
        return ancestor if (link_counts[key] ||= ancestor.css("a[href]").size) >= 3
      end
      nil
    end

    # Alike entries of one link each, perhaps with a count beside it, and
    # separators between them. Cards that link to their title, category and
    # author, or a post header whose title links to itself, are no menu. A
    # label may lead the entries ("Tags:"), but words between them make a
    # sentence or a list of names.
    def menu_entries?(holder)
      entries = []
      lead = 0
      holder.children.each do |child|
        if child.element? && (child.name == "a" || child.at_css("a[href]"))
          entries << child
        elsif entries.empty?
          lead += label_length(Dom.text(child))
        elsif Dom.text(child).match?(LETTER)
          return false
        end
      end
      return false if lead > MAX_LABEL || entries.size < 3 || entries.map(&:name).uniq.size > 1

      entries.all? { |entry| one_link?(entry) }
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

    def remove_with_label(node, root, repeated)
      labels = repeated.include?(shape(node)) ? [] : labels_of(node, root)
      remove(node)
      labels.each { |label| remove(label) }
    end

    # Alike boxes repeated down the page are the tags of a run of cards, and
    # the heading over each is the card's title.
    def repeated_shapes(boxes)
      boxes.group_by { |box| shape(box) }.select { |_, alike| alike.size >= MIN_SERIES }.keys.to_set
    end

    def shape(node)
      [node, node.parent].compact.flat_map { |element| [element.name, Dom.signature(element)] }
    end

    # The headings over a box of links label nothing once the box is gone,
    # unless more of their section follows. Widgets nest the box and its
    # heading in wrappers, each level with a heading of its own.
    def labels_of(node, root)
      labels = []
      holder = node
      loop do
        holder = holder.parent while only_child?(holder) && inside?(holder.parent, root)
        label = previous_content(holder)
        break unless label && section_label?(label) && section_end?(holder, root)

        labels << label
        break unless previous_content(label).nil? && next_content(holder).nil? && inside?(holder.parent, root)

        holder = holder.parent
      end
      labels
    end

    def only_child?(node)
      previous_content(node).nil? && next_content(node).nil?
    end

    # The next section starts after the box, or after the wrapper the box
    # ends: a card's body may follow in a row of its own below the row that
    # holds its title and tags.
    def section_end?(node, root)
      following = next_content(node)
      following = next_content(node.parent) if following.nil? && inside?(node.parent, root)
      following.nil? || section_start?(following)
    end

    def section_start?(node)
      node = node.children.find { |child| !blank?(child) } while node&.element? && !Dom.heading?(node)
      !node.nil? && Dom.heading?(node)
    end

    def previous_content(node)
      sibling = node.previous_sibling
      sibling = sibling.previous_sibling while sibling && blank?(sibling)
      sibling
    end

    def next_content(node)
      sibling = node.next_sibling
      sibling = sibling.next_sibling while sibling && blank?(sibling)
      sibling
    end

    # Comments, white space, rules and empty spacers hold nothing of a section.
    def blank?(node)
      return !node.text? || Dom.text(node).empty? unless node.element?

      !MEDIA.include?(node.name) && Dom.text(node).empty? && node.at_css(MEDIA_SELECTOR).nil?
    end

    # A short heading below the page title, a wrapper holding only one, or a
    # lead that ends in a colon ("Tags:"). A linked or long heading is the
    # title of a card, not a label, and a wrapper with a picture is a banner.
    def section_label?(node)
      text = Dom.text(node)
      return false if text.empty? || label_length(text) > MAX_LABEL || linked?(node)
      return true if text.match?(LEAD)
      return false unless node.element?
      return true if SECTION_HEADINGS.include?(node.name)
      return false if node.at_css(MEDIA_SELECTOR)

      node.css(SECTION_HEADING_SELECTOR).any? { |heading| Dom.text(heading) == text }
    end

    def linked?(node)
      return true if Dom.ancestors_named(node, "a").any? { |link| link["href"] }

      node.element? && ((node.name == "a" && !node["href"].nil?) || !node.at_css("a[href]").nil?)
    end

    def label_length(text)
      text.length + text.scan(WIDE).size * 2
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
      text_length.positive? && lengths.max < 30 && lengths.sum.fdiv(text_length) >= 0.7 && !in_sentence?(node)
    end

    # Links that a sentence names ("Become a member by purchasing
    # <span><a>Standard</a>, <a>Premium</a></span>!") are part of it.
    def in_sentence?(node)
      parent = node.parent
      return false if Dom.block?(node) || !parent&.element?

      parent.children.sum { |child| child.text? ? Dom.char_count(child.content) : 0 } >= SENTENCE_TEXT
    end

    def in_data_table?(node)
      tables = node.name == "table" ? [node] : []
      (tables + Dom.ancestors_named(node, "table")).any? { |table| data_table?(table) }
    end

    # Each row, cell and cluster of a long table asks about the same table.
    def data_table?(table)
      key = Dom.key(table)
      return Tables.data_table?(table) if key.nil?

      @data_tables.fetch(key) { @data_tables[key] = Tables.data_table?(table) }
    end

    def remove_boilerplate_text(root)
      notices = []
      root.css(TEXT_BLOCKS).each do |node|
        text = Dom.text(node)
        next if text.empty? || text.length > MAX_NOTICE

        if text.length <= 80 && text.match?(Patterns::BOILERPLATE_TEXT)
          remove(node)
        elsif copyright?(node, text)
          notices << node
        end
      end
      # Old sites lay their footer out in a table and set it in font tags.
      root.css(LAYOUT_CELLS).each do |node|
        next if Dom.char_count(node.content) > MAX_NOTICE

        notices << node if copyright?(node, Dom.text(node)) && !in_data_table?(node)
      end
      remove_notices(notices)
    end

    def copyright?(node, text)
      text.match?(Patterns::COPYRIGHT_TEXT) && node.at_css("img").nil?
    end

    # The smallest block carries the notice. The block around it goes too
    # when the rest of it is links and numbers ("Privacy | Terms", a visitor
    # counter), but not when it also holds a product's name and price.
    def remove_notices(notices)
      keys = notices.map { |node| Dom.key(node) }.to_set
      carriers = notices.reject { |node| node.css(NOTICE_BLOCKS).any? { |child| keys.include?(Dom.key(child)) } }
      carrier_keys = carriers.map { |node| Dom.key(node) }.to_set
      notices.each do |node|
        rest = carrier_keys.include?(Dom.key(node)) ? "" : Dom.squish(text_outside(node, carrier_keys))
        remove(node) if rest.match?(NO_WORDS)
      end
    end

    def text_outside(node, skipped)
      node.children.sum("") do |child|
        next " #{child.content}" if child.text?
        next "" if !child.element? || child.name == "a" || skipped.include?(Dom.key(child))

        text_outside(child, skipped)
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
      return true if node["role"] == "button" || BUTTON_PART.any? { |name| node[name] == "button" }
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

    # Site footers go by many names ("mFooter", "b-footer", "foot_section",
    # "agriFooterWrapper"), and a card or a post has a footer too. One that
    # almost nothing of the content follows is the site's, unless the main
    # landmark or an article holds it: there it ends that content, with its
    # notes or sources.
    def remove_tail_footers
      @tail_total = @nodes.sum { |root| Dom.char_count(root.content) }
      return if @tail_total < MIN_TAIL_TEXT

      @tail_limit = [@tail_total * TAIL_SHARE, TAIL_CHARS].max
      @footer_budget = @tail_total * MAX_TAIL_SHARE
      @footers = []
      after = 0
      @nodes.reverse_each { |root| after += walk_back(root, after) }
      @footers.each { |node| remove(node) }
    end

    # Visits the content from its end and returns the characters it visited,
    # so after is always what follows the node being visited. It stops at the
    # limit, and so does every walk above it.
    def walk_back(node, after)
      inside = 0
      node.children.reverse_each do |child|
        break if after + inside > @tail_limit

        inside += chars_back(child, after + inside)
      end
      inside
    end

    # A footer holding most of the content is the content, though the site's
    # footer can still end it.
    def chars_back(node, after)
      return Dom.char_count(node.content) if node.text? || (node.element? && Dom::CODE.include?(node.name))
      return 0 unless node.element?

      if site_footer?(node)
        chars = Dom.char_count(node.content)
        return take_footer(node, chars) if chars <= @footer_budget
      end
      walk_back(node, after)
    end

    def take_footer(node, chars)
      @footers << node
      @footer_budget -= chars
      chars
    end

    def site_footer?(node)
      return false unless footer_named?(node) && node.at_css("h1").nil?

      node.ancestors.none? { |ancestor| ancestor.element? && content_landmark?(ancestor) }
    end

    def content_landmark?(node)
      Boilerplate::CONTENT_ANCESTORS.include?(node.name) || node["role"] == "main" ||
        node["itemprop"].to_s.include?("articleBody")
    end

    def footer_named?(node)
      signature = Dom.signature(node).gsub(Patterns::TAXONOMY_TERM, " ")
      return false if signature.match?(Patterns::UNIT_FOOTER)
      return page_footer?(node) if node.name == "footer"

      signature.match?(Patterns::FOOTER_NAME)
    end

    # A footer element belongs to its quote or its section, and ends the page
    # only when that section wraps most of it.
    def page_footer?(node)
      return false if QUOTES.include?(node.parent&.name)

      section = node.ancestors.find { |ancestor| ancestor.element? && SECTIONS.include?(ancestor.name) }
      section.nil? || Dom.char_count(section.content) >= @tail_total * MAX_TAIL_SHARE
    end

    # Every rule removes through here: nothing inside code is furniture.
    def remove(node)
      node.remove unless Dom.in_code?(node)
    end
  end
end

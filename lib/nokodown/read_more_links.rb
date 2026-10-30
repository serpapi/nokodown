# frozen_string_literal: true

module Nokodown
  # A short link to the page that a longer link in the same card already
  # names ("Read more", "Leer más", "詳細を見る", "Comprar >" under a linked
  # title) says nothing in any language that the title does not. Dates and
  # counts carry digits and stay, and so does a link that a sentence, a
  # breadcrumb or a list runs through. This works in one card at a time, so
  # it also takes the label of a page's only teaser, which
  # Markdown::CardLinks leaves for not repeating across cards.
  class ReadMoreLinks
    Link = Struct.new(:node, :page, :text, :position)

    MAX_LABEL = 30
    MAX_WORDS = 4
    MAX_UNSPACED = 12
    # The most text a card holding both links may have.
    CARD_LENGTH = 1500
    # Cards sit next to each other, so the nearest longer links are the
    # ones that can share a card with the label.
    NEAREST = 2
    NEAREST_SCAN = 10
    MENU_ENTRIES = 3
    LABEL_HOLDERS = %w[h1 h2 h3 h4 h5 h6 dt th caption figcaption].freeze
    MEDIA = %w[img picture video audio iframe svg object embed].freeze
    MEDIA_SELECTOR = MEDIA.join(", ").freeze
    # A domain names a story's source and a format a dataset's file, facts
    # about the item like a badge: "vice.com", "CSV".
    FACT = /\A(?:[\p{L}\d-]+(?:\.[\p{L}\d-]+)+|pdf|csv|json|xml|rdf|kml|geojson|txt|zip|docx?|xlsx?|pptx?|odt|ods|epub|html?)\z/i.freeze
    DATE_OR_TIME = %r{\d{1,2}:\d{2}|\d{1,4}[./-]\d{1,2}[./-]\d{1,4}}.freeze
    # An excerpt the label follows ends like a sentence or with "[…]".
    EXCERPT_END = /[.…!?。！？\])]\z/.freeze

    def initialize(root)
      @root = root
      @chars = {}
      @data_tables = {}
    end

    def call
      links = @root.css("a[href]").each_with_index.map { |node, index| Link.new(node, page(node), Dom.text(node), index) }
      by_page = links.select { |link| destination?(link.page) }.group_by(&:page)
      namers = by_page.transform_values { |group| group.select { |link| namer?(link) } }
      holders = by_page.values.flatten.filter_map do |link|
        next unless label?(link)

        holder = holder(link)
        holder if standalone?(holder) && !menu_entry?(holder) && named_in_card?(link, holder, namers[link.page])
      end
      holders.each { |holder| holder.remove unless Dom.in_code?(holder) }
    end

    private

    # Where the link goes, with or without its scheme. Links to different
    # sections of one page go to different places.
    def page(node)
      node["href"].to_s.strip.sub(%r{\Ahttps?:(?=//)}i, "").sub(%r{/(?=\z|#)}, "")
    end

    # Placeholders such as "#" and "javascript:void(0)" lead nowhere, so
    # links sharing them are not about one page.
    def destination?(page)
      !page.empty? && !page.start_with?("#") && !page.match?(/\A(?:javascript|mailto|tel):/i)
    end

    # Scripts written without spaces fit a sentence in MAX_LABEL characters.
    # A file's format names the download, in a data table a link is a
    # cell's value, and a menu item over a submenu names it.
    def label?(link)
      text = link.text
      return false if text.empty? || text.length > MAX_LABEL || text.match?(/\d/) || text.match?(FACT)
      return false if text.include?(" ") ? text.split.size > MAX_WORDS : text.length > MAX_UNSPACED
      return false if link.page.sub(/[?#].*/m, "").match?(Pruner::DOWNLOAD) || link.node.at_css("img")

      ancestors = link.node.ancestors.select(&:element?)
      return false if ancestors.any? { |node| LABEL_HOLDERS.include?(node.name) }
      return false if ancestors.find { |node| node.name == "li" }&.at_css("ul, ol")

      ancestors.none? { |node| node.name == "table" && data_table?(node) }
    end

    # A reference table can hold thousands of links, so each table is
    # judged once.
    def data_table?(table)
      key = Dom.key(table)
      @data_tables.key?(key) ? @data_tables[key] : (@data_tables[key] = Tables.data_table?(table))
    end

    # The link with the elements that hold only it.
    def holder(link)
      holder = link.node
      holder = holder.parent while wrapper?(holder.parent, holder)
      holder
    end

    # Read from the node's siblings, nearest first: the text of a large
    # parent costs as much as the page.
    def wrapper?(parent, node)
      return false unless parent&.element? && Dom.key(parent) != Dom.key(@root)

      blank_side?(node, :previous_sibling) && blank_side?(node, :next_sibling)
    end

    def blank_side?(node, direction)
      sibling = node.send(direction)
      sibling = sibling.send(direction) while sibling && blank?(sibling)
      sibling.nil?
    end

    # An image or an embedded video beside the label is content of its own.
    def blank?(node)
      return false unless Dom.text(node).empty?

      !node.element? || !(MEDIA.include?(node.name) || node.at_css(MEDIA_SELECTOR))
    end

    # A link alone in an item of a list is an entry of a menu, a breadcrumb
    # or a table of contents, whose other entries lead elsewhere.
    def menu_entry?(holder)
      holder.name == "li" && holder.parent.element_children.count { |child| child.name == "li" } >= MENU_ENTRIES
    end

    # On a line of its own, at the end of an excerpt or in a row of
    # controls; not where a word, a colon or a separator leads into it, nor
    # over a line of its own, as a name over a person's dates.
    def standalone?(holder)
      return true if Dom.block?(holder)

      before = neighbour_text(holder, :previous_sibling, %w[a br])
      neighbour_text(holder, :next_sibling, %w[a]).empty? && (before.empty? || before.match?(EXCERPT_END))
    end

    # The text beside the node in its block, up to another link or, when
    # `stops` has it, a line break.
    def neighbour_text(node, direction, stops)
      sibling = node.send(direction)
      sibling = sibling.send(direction) while sibling && !boundary?(sibling, stops) && Dom.text(sibling).empty?
      sibling.nil? || boundary?(sibling, stops) ? "" : Dom.text(sibling)
    end

    def boundary?(node, stops)
      node.element? && (stops.include?(node.name) || Dom.block?(node))
    end

    # A link in words can name its page. A term of a definition list is
    # written without its link, so it does not, and neither does a date,
    # which can be longer than an event's name.
    def namer?(link)
      link.text.match?(/\p{L}/) && !link.text.match?(DATE_OR_TIME) && Dom.ancestors_named(link.node, "dt").empty? &&
        written?(link.node)
    end

    # Markdown::Renderer writes a link around blocks on their heading, or on
    # their first line of text when that holds no image or link; around
    # anything else (a team's name beside its logo) the link is lost.
    def written?(node)
      blocks = node.css("*").select { |child| Dom.block?(child) }
      return true if blocks.empty? || blocks.any? { |block| Dom.heading?(block) }

      line = blocks.find { |block| !Dom.text(block).empty? && block.css("*").none? { |child| Dom.block?(child) } }
      !line.nil? && line.at_css("img, a").nil?
    end

    # Controls follow what they act on, so the nearest longer links before
    # the label are the ones to check; a badge before a title ("HD", "New")
    # is a fact about the item.
    def named_in_card?(label, holder, namers)
      count = namers.bsearch_index { |link| link.position >= label.position } || namers.size
      before = namers[[0, count - NEAREST_SCAN].max...count]
      longer = before.reverse.select { |link| link.text.length > label.text.length && !thumbnail?(link, label) }.first(NEAREST)
      longer.any? { |link| same_card?(holder, label.node, link.node) }
    end

    # The text of a thumbnail is often the counts and badges over its image
    # ("Episode 54 added", "720p"), and its alt the name the label gives.
    def thumbnail?(link, label)
      media = link.node.css(MEDIA_SELECTOR)
      return false if media.empty?

      link.text.match?(/\d/) || media.any? { |node| Dom.squish(node["alt"].to_s).casecmp?(label.text) }
    end

    # Both links in one card, but not side by side like the items of a list,
    # a row of links to one page under different names, or two people of a
    # family table placed alike.
    def same_card?(holder, label, other)
      keys = other.ancestors.select(&:element?).map { |ancestor| Dom.key(ancestor) }.to_set
      common = holder.ancestors.find { |ancestor| ancestor.element? && keys.include?(Dom.key(ancestor)) }
      return false if common.nil? || chars(common) > CARD_LENGTH || shape(label, common) == shape(other, common)

      Dom.key(common) != Dom.key(holder.parent) || branch(other, common).name != holder.name
    end

    def shape(node, ancestor)
      shape = []
      until Dom.key(node) == Dom.key(ancestor)
        shape << [node.name, node["class"]]
        node = node.parent
      end
      shape
    end

    # Labels in a grid share their containers, so each is measured once.
    def chars(node)
      @chars[Dom.key(node)] ||= Dom.char_count(node.content)
    end

    # The child of the common ancestor that holds the other link.
    def branch(node, ancestor)
      node = node.parent until Dom.key(node.parent) == Dom.key(ancestor)
      node
    end
  end
end

# frozen_string_literal: true

module Nokodown
  # A short link to the page that a longer link in the same card already
  # names ("Read more", "Leer más", "詳細を見る", "Comprar >" under a linked
  # title) says nothing in any language that the title does not. Dates and
  # counts carry digits and stay, and so does a link that a sentence, a
  # breadcrumb or a list runs through.
  class RepeatedLinks
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
    LABEL_HOLDERS = %w[h1 h2 h3 h4 h5 h6 dt th caption figcaption].freeze
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
        holder if standalone?(holder) && named_in_card?(link, holder, namers[link.page])
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
      return false if text.empty? || text.length > MAX_LABEL || text.match?(/\d/)
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
      sibling = sibling.send(direction) while sibling && Dom.text(sibling).empty?
      sibling.nil?
    end

    # On a line of its own, at the end of an excerpt or in a row of
    # controls; not where a word, a colon or a separator leads into it.
    def standalone?(holder)
      return true if Dom.block?(holder)

      before = neighbour_text(holder, :previous_sibling)
      neighbour_text(holder, :next_sibling).empty? && (before.empty? || before.match?(EXCERPT_END))
    end

    # The text beside the node in its line. A block, a line break or
    # another link ends it.
    def neighbour_text(node, direction)
      sibling = node.send(direction)
      sibling = sibling.send(direction) while sibling && !boundary?(sibling) && Dom.text(sibling).empty?
      sibling.nil? || boundary?(sibling) ? "" : Dom.text(sibling)
    end

    def boundary?(node)
      node.element? && (%w[a br].include?(node.name) || Dom.block?(node))
    end

    # A link in words can name its page. A term of a definition list is
    # written without its link, so it does not.
    def namer?(link)
      link.text.match?(/\p{L}/) && Dom.ancestors_named(link.node, "dt").empty?
    end

    # Controls follow what they act on, so the nearest longer links before
    # the label are the ones to check; a badge before a title ("HD", "New")
    # is a fact about the item.
    def named_in_card?(label, holder, namers)
      count = namers.bsearch_index { |link| link.position >= label.position } || namers.size
      before = namers[[0, count - NEAREST_SCAN].max...count]
      longer = before.reverse.select { |link| link.text.length > label.text.length }.first(NEAREST)
      longer.any? { |link| same_card?(holder, link.node) }
    end

    # Both links in one card, but not side by side like the items of a list
    # or a row of links to one page under different names.
    def same_card?(holder, other)
      keys = other.ancestors.select(&:element?).map { |ancestor| Dom.key(ancestor) }.to_set
      common = holder.ancestors.find { |ancestor| ancestor.element? && keys.include?(Dom.key(ancestor)) }
      return false if common.nil? || chars(common) > CARD_LENGTH

      Dom.key(common) != Dom.key(holder.parent) || branch(other, common).name != holder.name
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

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
    LABEL_HOLDERS = %w[h1 h2 h3 h4 h5 h6 dt th caption figcaption].freeze
    # An excerpt the label follows ends like a sentence or with "[…]".
    EXCERPT_END = /[.…!?。！？\])]\z/.freeze

    def initialize(root)
      @root = root
    end

    def call
      links = @root.css("a[href]").each_with_index.map { |node, index| Link.new(node, page(node), Dom.text(node), index) }
      by_page = links.select { |link| destination?(link.page) }.group_by(&:page)
      holders = by_page.values.flatten.filter_map do |link|
        next unless label?(link)

        holder = holder(link)
        holder if standalone?(holder) && named_in_card?(link, holder, by_page[link.page])
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
      return false if link.node.at_css("img") || Dom.ancestors_named(link.node, *LABEL_HOLDERS).any?
      return false if link.page.sub(/[?#].*/m, "").match?(Pruner::DOWNLOAD)
      return false if Dom.ancestors_named(link.node, "li").first&.at_css("ul, ol")

      Dom.ancestors_named(link.node, "table").none? { |table| Tables.data_table?(table) }
    end

    # The link with the elements that hold only it.
    def holder(link)
      holder = link.node
      holder = holder.parent while holder.parent&.element? && Dom.key(holder.parent) != Dom.key(@root) &&
                                   Dom.text(holder.parent) == link.text
      holder
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

    # Controls follow what they act on; a badge before a title ("HD",
    # "New") is a fact about the item.
    def named_in_card?(label, holder, links)
      longer = links.select do |link|
        link.position < label.position && link.text.length > label.text.length && link.text.match?(/\p{L}/)
      end
      longer.min_by(NEAREST) { |link| (link.position - label.position).abs }.any? { |link| same_card?(holder, link.node) }
    end

    # Both links in one card, but not side by side like the items of a list
    # or a row of links to one page under different names.
    def same_card?(holder, other)
      keys = other.ancestors.select(&:element?).map { |ancestor| Dom.key(ancestor) }.to_set
      common = holder.ancestors.find { |ancestor| ancestor.element? && keys.include?(Dom.key(ancestor)) }
      return false if common.nil? || Dom.char_count(common.content) > CARD_LENGTH

      Dom.key(common) != Dom.key(holder.parent) || branch(other, common).name != holder.name
    end

    # The child of the common ancestor that holds the other link.
    def branch(node, ancestor)
      node = node.parent until Dom.key(node.parent) == Dom.key(ancestor)
      node
    end
  end
end

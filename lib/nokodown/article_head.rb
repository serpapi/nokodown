# frozen_string_literal: true

module Nokodown
  # What sits between the page's headline and the body that scoring picked
  # belongs to the article: a standfirst, the key facts of a home for sale,
  # an event's date and place, a product's price. None of it is prose, so
  # none of it scores. When that stretch is short and not a list of links,
  # such as a menu, the article becomes the element holding the headline and
  # the body, cut to run from the one to the other, so nothing before the
  # headline or after the body comes in with it.
  class ArticleHead
    MAX_CHARS = 600
    MAX_LINK_DENSITY = 0.5
    TITLE_MATCH = 0.5
    HEADINGS = "h1, h2, h3, h4, h5, h6"

    def initialize(root, nodes, stats, title = nil)
      @root = root
      @nodes = nodes
      @stats = stats
      @title = title
    end

    def call
      return @nodes if @nodes.any? { |node| node.name == "h1" || node.at_css("h1") }

      body = @nodes.first
      headline = @root.css("h1").select { |h1| Dom.key(h1).to_i < Dom.key(body).to_i }.last
      return @nodes unless headline && page_headline?(headline)

      holder = shared_ancestor(headline, body)
      stretch = between(headline, body, holder)
      return @nodes unless short?(stretch) && !rival?(headline, stretch)

      cut(holder, headline)
      [holder]
    end

    private

    # A blog's name linked to its home page, or a section label such as
    # "News" or "Blog", is an H1 above the article that does not name it.
    def page_headline?(headline)
      text = Dom.text(headline)
      return false if text.empty? || headline.css("a[href]").any? { |link| home_link?(link["href"].strip) }

      @title.nil? || match(text).max >= TITLE_MATCH
    end

    def home_link?(href)
      !href.empty? && !href.start_with?("#", "?") && href.match?(Metadata::HOME_LINK)
    end

    # A heading below that names the page better is the article's own, and
    # the H1 above it a site name or a section label in the title.
    def rival?(headline, stretch)
      return false if @title.nil?

      own = match(Dom.text(headline)).min
      headings = (stretch.drop(1) + @nodes).flat_map { |node| Dom.heading?(node) ? [node] : node.css(HEADINGS).to_a }
      headings.any? { |heading| (rival = match(Dom.text(heading)).min) >= TITLE_MATCH && rival > own }
    end

    # How much of the text the title covers, and how much of the title it does.
    def match(text)
      [Dom.similarity(@title, text), Dom.similarity(text, @title)]
    end

    def shared_ancestor(node, other)
      keys = other.ancestors.map { |ancestor| Dom.key(ancestor) }.to_set
      node.ancestors.find { |ancestor| keys.include?(Dom.key(ancestor)) }
    end

    # The elements from `first` up to `last` in document order, each taken
    # whole where it can be: up from `first` to the branch the two share,
    # across it, then down to `last`.
    def between(first, last, holder)
      down = path_to(last, holder)
      up = path_to(first, holder)
      head = [first]
      up[0...-1].each { |node| head.concat(following(node)) }
      head.concat(following(up.last).take_while { |node| Dom.key(node) != Dom.key(down.last) })
      down[0...-1].reverse_each { |node| head.concat(preceding(node)) }
      head
    end

    def cut(holder, headline)
      path_to(headline, holder).each { |node| preceding(node).each(&:remove) }
      kept = @nodes.map { |node| Dom.key(node) }.to_set
      parent = @nodes.first.parent
      later = parent.element_children.drop_while { |child| !kept.include?(Dom.key(child)) }
      later.each { |child| child.remove unless kept.include?(Dom.key(child)) }
      path_to(parent, holder).each { |node| following(node).each(&:remove) }
    end

    # The node and its ancestors below `top`.
    def path_to(node, top)
      [node, *node.ancestors.select(&:element?)].take_while { |step| Dom.key(step) != Dom.key(top) }
    end

    def following(node)
      siblings = []
      sibling = node.next_element
      while sibling
        siblings << sibling
        sibling = sibling.next_element
      end
      siblings
    end

    def preceding(node)
      node.parent.element_children.take_while { |sibling| Dom.key(sibling) != Dom.key(node) }
    end

    def short?(stretch)
      chars = stretch.sum { |node| @stats.chars(node) }
      chars <= MAX_CHARS && (chars.zero? || stretch.sum { |node| @stats.link_chars(node) } / chars < MAX_LINK_DENSITY)
    end
  end
end

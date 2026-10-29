# frozen_string_literal: true

module Nokodown
  # What sits between the page's headline and the body that scoring picked
  # belongs to the article: a standfirst, the key facts of a home for sale,
  # an event's date and place, a product's price. None of it is prose, so
  # none of it scores. When that stretch is short and not a list of links,
  # such as a slider or a menu, the article becomes the element holding the
  # headline and the body, cut to run from the one to the other: what comes
  # before the headline or after the body is no more part of it than before.
  class ArticleHead
    MAX_CHARS = 600
    MAX_LINK_DENSITY = 0.5

    def initialize(root, nodes, stats)
      @root = root
      @nodes = nodes
      @stats = stats
    end

    def call
      return @nodes if @nodes.any? { |node| node.name == "h1" || node.at_css("h1") }

      body = @nodes.first
      headline = @root.css("h1").select { |h1| Dom.key(h1).to_i < Dom.key(body).to_i }.last
      return @nodes unless headline && short?(between(headline, body))

      holder = shared_ancestor(headline, body)
      cut(holder, headline)
      [holder]
    end

    private

    def shared_ancestor(node, other)
      keys = other.ancestors.map { |ancestor| Dom.key(ancestor) }.to_set
      node.ancestors.find { |ancestor| keys.include?(Dom.key(ancestor)) }
    end

    # The elements from `first` up to `last` in document order, each taken
    # whole where it can be: up from `first` to the branch the two share,
    # across it, then down to `last`.
    def between(first, last)
      down = path_to(last, shared_ancestor(first, last))
      up = path_to(first, shared_ancestor(first, last))
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

    def short?(head)
      chars = head.sum { |node| @stats.chars(node) }
      chars <= MAX_CHARS && (chars.zero? || head.sum { |node| @stats.link_chars(node) } / chars < MAX_LINK_DENSITY)
    end
  end
end

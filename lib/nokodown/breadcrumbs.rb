# frozen_string_literal: true

module Nokodown
  # Breadcrumb trails that no class or role names: "Home > Category > Page"
  # in any language. A trail starts at the site's home page, links only
  # within the site, and holds nothing but its links, the separators
  # between them, the current page's name at the end and an optional label
  # before it ("You are here:", "当前位置："). Without separators only an
  # ordered list reads as a trail; a plain list of links is a menu.
  module Breadcrumbs
    HOME = %r{
      \A(?:https?:)?//[^/?#]+/?(?:(?:index|default|home)\.\w+|[a-z]{2}(?:[-_][a-z]{2})?/?)?\z|
      \A\.?/(?:(?:index|default|home)\.\w+|[a-z]{2}(?:[-_][a-z]{2})?/?)?\z|
      \A(?:index|default|home)\.\w+\z
    }xi.freeze
    HOST = %r{\A(?:https?:)?//(?:www\.)?([^/?#]+)}i.freeze
    # Dashes and colons also join a link to its description in a list of
    # resources ("Salary.com – salaries by zip code"), and a bar to a
    # tagline; a lone link needs a mark that only points down a trail.
    DOWN_MARKS = '>/»›→\\\\＞〉'
    TRAIL_MARKS = "#{DOWN_MARKS}|"
    MARKS = "#{TRAIL_MARKS}\\-–·•:~"
    SEPARATOR = /\A[\s#{MARKS}]+/.freeze
    ONLY_SEPARATORS = /\A[\s#{MARKS}]*\z/.freeze
    TRAIL_MARK = /[#{TRAIL_MARKS}]/.freeze
    DOWN_MARK = /\A\s*[#{DOWN_MARKS}]/.freeze
    # The page's name follows the last link the way each link follows the
    # one before ("› Page", "-> Page"); other text after it is a sentence.
    LEAD_MARK = /\A[\s\-–]*[#{TRAIL_MARKS}]/.freeze
    LABEL = /[:：]\z/.freeze
    # "20.07.2026 08:42" after a category link is the post's date line.
    DATE = %r{\d{1,4}[./-]\d{1,2}[./-]\d{1,4}|\d{1,2}:\d{2}}.freeze
    MAX_LINKS = 8
    MAX_CHARS = 300
    MAX_LABEL = 25
    MAX_CURRENT = 150

    module_function

    # Link farms point hundreds of links at home pages from one container,
    # so each container is judged once.
    def trails(body)
      checked = Set.new
      links = body.css("a[href]")
      site = site_host(links)
      links.filter_map do |link|
        next if !link["href"].strip.match?(HOME) || checked.include?(Dom.key(link.parent))

        node = container(link)
        node if node && checked.add?(Dom.key(node)) && trail_at?(node, link, site)
      end
    end

    # The host most links point to is the site's own.
    def site_host(links)
      hosts = links.filter_map { |link| link["href"].strip[HOST, 1]&.downcase }
      hosts.tally.max_by { |_, count| count }&.first
    end

    # Up from the home link past the wrappers that add only separators, to
    # the element that holds the rest of the trail.
    def container(home)
      path = home
      node = home.parent
      while node&.element? && node.name != "body" && wrapper?(node, path)
        path = node
        node = node.parent
      end
      node if node&.element? && node.name != "body"
    end

    def trail_at?(node, home, site)
      return false if Dom.text(node).length > MAX_CHARS

      links = node.css("a[href]").to_a
      return false unless links.size <= MAX_LINKS && Dom.key(links.first) == Dom.key(home) && same_site?(links)
      # A lone link to another site's home page credits or cites that site.
      return false if links.size == 1 && !own_site?(home, site)

      trail?(node, gaps(node))
    end

    def own_site?(link, site)
      host = link["href"].strip[HOST, 1]&.downcase
      host.nil? || host == site
    end

    # Children are judged one by one, so a container of many links stops the
    # walk at its first other link. They are read one at a time too: listing
    # them first listed a link farm's thousands of home links for each one.
    def wrapper?(node, path)
      key = Dom.key(path)
      child = node.child
      while child
        return false unless wrapped?(child, key)

        child = child.next_sibling
      end
      true
    end

    def wrapped?(child, key)
      if child.text?
        Dom.squish(child.content).match?(ONLY_SEPARATORS)
      elsif child.element?
        Dom.key(child) == key || separator_element?(child)
      else
        true
      end
    end

    def separator_element?(node)
      node.name != "a" && Dom.text(node).match?(ONLY_SEPARATORS) && node.at_css("a[href]").nil?
    end

    def same_site?(links)
      links.map { |link| link["href"].strip[HOST, 1]&.downcase }.compact.uniq.size <= 1
    end

    # The text before, between and after the links, one string per gap.
    def gaps(node)
      gaps = [+""]
      node.traverse do |child|
        if child.element? && child.name == "a" && child["href"]
          gaps << +""
        elsif child.text? && !inside_link?(child, node)
          gaps.last << " " << child.content
        end
      end
      gaps.map { |gap| Dom.squish(gap) }
    end

    def inside_link?(text_node, root)
      text_node.ancestors.each do |ancestor|
        return false if Dom.key(ancestor) == Dom.key(root)
        return true if ancestor.name == "a" && ancestor["href"]
      end
      false
    end

    # A lone home link needs the page's name after it, and so does an
    # ordered list without marks, or it is a numbered list of links.
    def trail?(node, gaps)
      between = gaps[1...-1]
      trailing = gaps.last
      return false unless label?(gaps.first) && current_page?(trailing)
      return false unless between.all? { |gap| gap.match?(ONLY_SEPARATORS) }
      return true if node.name == "ol" && !trailing.empty?
      return false unless trailing.empty? || trailing.match?(LEAD_MARK)

      between.empty? ? trailing.match?(DOWN_MARK) : between.any? { |gap| gap.match?(TRAIL_MARK) }
    end

    def label?(leading)
      leading.empty? || (leading.length <= MAX_LABEL && leading.match?(LABEL))
    end

    def current_page?(trailing)
      name = trailing.sub(SEPARATOR, "")
      name.length <= MAX_CURRENT && !name.match?(DATE)
    end
  end
end

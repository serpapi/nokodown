# frozen_string_literal: true

module Nokodown
  # Posts on a blog index, products in a category, events in a calendar:
  # runs of sibling items alike in tag and leading class, each linking to its
  # own page, that hold most of the content's own text. Items differ in post
  # ids and category classes, so only the leading class is compared. Cards
  # that are only a linked headline hold no text of their own: they point to
  # other stories rather than list this page's.
  module Listing
    ITEM_TAGS = Set.new(%w[article div li section]).freeze
    # Unnamed divs and sections are layout columns, not items.
    UNNAMED_ITEMS = Set.new(%w[article li]).freeze
    MIN_ITEMS = 3
    SHARE = 0.5
    # An item has a title and perhaps a subtitle; page sections and columns,
    # one of which can be the article itself, have more headings.
    MAX_HEADINGS = 2
    RECORD_PARTS = "table, pre, code"
    SCRIPT_LINK = /\Ajavascript:/i.freeze

    module_function

    # Keys of the listings' items, of everything inside them and of the
    # elements around them, for conditional cleaning to leave alone.
    def keys(roots)
      roots.flat_map { |root| items(root) }.each_with_object(Set.new) do |item, keys|
        [item, *item.css("*"), *item.ancestors.select(&:element?)].each { |node| keys << Dom.key(node) }
      end
    end

    # Every run counts once the runs together hold most of the text: a shop's
    # home page lists products, with prices for text, beside posts.
    def items(root)
      stats = Stats.new(root)
      total = stats.text_chars(root)
      return [] if total.zero?

      runs = [root, *root.css("*")].flat_map { |parent| item_runs(parent, stats).map { |run| [parent, run] } }
      items = runs.flat_map(&:last)
      return [] if outermost(items).sum { |item| stats.text_chars(item) } < total * SHARE

      items + runs.flat_map { |parent, run| featured(parent, run) }
    end

    def outermost(items)
      keys = items.map { |item| Dom.key(item) }.to_set
      items.reject { |item| item.ancestors.any? { |ancestor| ancestor.element? && keys.include?(Dom.key(ancestor)) } }
    end

    # Joomla and others lead with a featured post outside the run, in a block
    # of its own beside the run or its wrapper.
    def featured(parent, items)
      taken = [*items, parent].map { |node| Dom.key(node) }.to_set
      [parent, parent.parent].select(&:element?).flat_map(&:element_children).select do |child|
        !taken.include?(Dom.key(child)) && child.css(Dom::HEADING_SELECTOR).any? { |heading| linked?(heading) }
      end
    end

    # Menus and grids of linked headlines hold no text of their own.
    def item_runs(parent, stats)
      items = parent.element_children.select { |child| ITEM_TAGS.include?(child.name) }
      return [] if items.size < MIN_ITEMS

      runs = items.group_by { |item| [item.name, item["class"].to_s.split.first.to_s.delete("0-9")] }
      runs.filter_map do |(name, leading), run|
        next if run.size < MIN_ITEMS || (leading.empty? && !UNNAMED_ITEMS.include?(name))

        run if run.count { |item| stats.text_chars(item).positive? } * 2 >= run.size && run.all? { |item| teaser?(item) }
      end
    end

    # A teaser links to a page of its own, and a title it has is that link.
    # Documentation sections link their headings to themselves, and reference
    # entries hold signatures, parameter tables and code.
    def teaser?(item)
      headings = item.css(Dom::HEADING_SELECTOR)
      return false if headings.size > MAX_HEADINGS || item.at_css(RECORD_PARTS)
      return false if item.css("a[href]").none? { |link| page_link?(link) }

      headings.empty? || headings.any? { |heading| linked?(heading) }
    end

    def linked?(heading)
      links = heading.css("a[href]").to_a + Dom.ancestors_named(heading, "a")
      links.any? { |link| page_link?(link) }
    end

    def page_link?(link)
      href = link["href"].to_s.strip
      !href.empty? && !href.start_with?("#") && !href.match?(SCRIPT_LINK)
    end
  end
end

# frozen_string_literal: true

module Nokodown
  # Posts on a blog index, products in a category, events in a calendar: a
  # run of sibling items alike in tag and leading class, each linking to its
  # own page, that holds most of the content's own text. Items differ in post
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
    HEADINGS = "h1, h2, h3, h4, h5, h6"

    module_function

    def listing?(root)
      stats = Stats.new(root)
      needed = stats.text_chars(root) * SHARE
      return false if needed.zero?

      [root, *root.css("*")].any? do |parent|
        item_runs(parent).any? { |run| run.sum { |item| stats.text_chars(item) } >= needed }
      end
    end

    def item_runs(parent)
      items = parent.element_children.select { |child| ITEM_TAGS.include?(child.name) }
      return [] if items.size < MIN_ITEMS

      runs = items.group_by { |item| [item.name, item["class"].to_s.split.first.to_s.delete("0-9")] }
      runs.filter_map { |(name, leading), run| run if item_run?(name, leading, run) }
    end

    def item_run?(name, leading, run)
      return false if run.size < MIN_ITEMS || (leading.empty? && !UNNAMED_ITEMS.include?(name))

      run.all? { |item| item.at_css("a[href]") && item.css(HEADINGS).size <= MAX_HEADINGS }
    end
  end
end

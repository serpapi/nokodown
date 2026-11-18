# frozen_string_literal: true

module Nokodown
  # Page numbers ("« 1 2 3 4 5 … 47 »") and archive calendars of day links.
  # They lead to the other pages of a listing or to other days' posts and
  # say nothing of this page. When the current number is plain text there
  # is no link to the page itself for the menu rules to find.
  module Pagers
    NUMBER = /\A\d{1,5}\z/.freeze
    TOKEN = /\d+|\p{L}+|[^\s\p{L}\d]+/.freeze
    # What a pager holds besides its numbers: arrows, ellipses, separators,
    # "Page", "Pages:", "of", first, last, previous and next.
    FILLER = /
      \A(?:[^\p{L}\d]+|page[sn]?|pagina|página|seiten?|страниц[аы]?|of|von|из|de|sur|first|last|
      #{Patterns::PREV_NEXT.source})\z
    /xi.freeze
    MIN_RUN = 5
    MIN_LINKS = 4
    MIN_DAYS = 28
    MAX_DAYS = 31
    # Weekday names over the days, in any language ("Mo", "Пн", "一").
    MAX_WEEKDAY = 3

    module_function

    # The outermost elements under each root that hold only a pager or a
    # calendar.
    def find(root)
      judged = {}
      calendars = {}
      found = root.css("a[href]").filter_map do |link|
        next unless Dom.text(link).match?(NUMBER)

        calendar(link, root, calendars) || outermost(link, root, judged)
      end
      found.uniq { |node| Dom.key(node) }
    end

    def outermost(link, root, judged)
      found = nil
      node = link.parent
      while node&.element? && Dom.key(node) != Dom.key(root)
        key = Dom.key(node)
        judged[key] = pager?(node) unless judged.key?(key)
        break unless judged[key]

        found = node
        node = node.parent
      end
      found
    end

    # A run of consecutive numbers, most of them links; the current one may
    # be plain or bold.
    def pager?(node)
      tokens = Dom.text(node).scan(TOKEN)
      numbers = tokens.grep(NUMBER).map(&:to_i)
      return false if numbers.size < MIN_RUN || tokens.any? { |token| !token.match?(NUMBER) && !token.match?(FILLER) }
      return false unless numbers.each_cons(2).all? { |a, b| b > a }

      longest_step_run(numbers) >= MIN_RUN && node.css("a[href]").size >= MIN_LINKS
    end

    def longest_step_run(numbers)
      runs = numbers.slice_when { |a, b| b != a + 1 }
      runs.map(&:size).max
    end

    def calendar(link, root, calendars)
      table = Dom.ancestors_named(link, "table").first
      return unless table && inside?(table, root)

      key = Dom.key(table)
      calendars[key] = calendar?(table) unless calendars.key?(key)
      table if calendars[key]
    end

    def inside?(node, root)
      key = Dom.key(root)
      node.ancestors.any? { |ancestor| ancestor.element? && Dom.key(ancestor) == key }
    end

    # Days 1 to 28-31 in order, under weekday names. The caption and the
    # footer name the month and link to the months around it.
    def calendar?(table)
      days = []
      table.css("td, th").each do |cell|
        next if Dom.ancestors_named(cell, "tfoot").any?

        text = Dom.text(cell)
        if text.match?(NUMBER)
          days << text.to_i
        elsif text.length > MAX_WEEKDAY
          return false
        end
      end
      days.size.between?(MIN_DAYS, MAX_DAYS) && days == (1..days.size).to_a
    end
  end
end

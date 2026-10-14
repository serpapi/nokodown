# frozen_string_literal: true

module Nokodown
  # Decides what part of the cleaned page is the content.
  #
  # Pages with one dominant body of prose (articles, posts, documentation)
  # are narrowed to that body using Readability's scoring. Everything else
  # (home pages, listings, product pages, pricing tables) keeps the whole main
  # region, because there the content is spread across many small blocks and
  # picking a single winner would throw most of it away.
  class ContentLocator
    Selection = Struct.new(:nodes, :mode)

    MIN_ARTICLE_CHARS = 250

    # Share of the page's prose the article candidate must hold, by the page
    # type its metadata declares. A declared article only needs a real body.
    REQUIRED_SHARE = { article: 0.15, product: 0.9 }.freeze
    DEFAULT_SHARE = 0.7

    def initialize(body, page_type: nil)
      @body = body
      @page_type = page_type
    end

    def call
      stats = Stats.new(@body)
      root = main_region(stats) || @body
      result = Scorer.new(root, stats).call
      return Selection.new(result.nodes, :article) if result && article?(result, root, stats)

      Selection.new([root], :page)
    end

    private

    # The outermost <main> holding a fair share of the page, if any.
    def main_region(stats)
      regions = @body.css("main, [role=main]").reject do |node|
        node.ancestors.any? { |ancestor| ancestor.element? && (ancestor.name == "main" || ancestor["role"] == "main") }
      end
      best = regions.max_by { |node| stats.text_chars(node) }
      best if best && stats.text_chars(best) >= stats.text_chars(@body) * 0.4
    end

    def article?(result, root, stats)
      article_text = result.nodes.sum { |node| stats.text_chars(node) }
      return false if article_text < MIN_ARTICLE_CHARS

      page_text = stats.text_chars(root) - secondary_text(root, result.nodes, stats)
      return true if page_text <= 0

      article_text / page_text >= REQUIRED_SHARE.fetch(@page_type, DEFAULT_SHARE)
    end

    # Comment threads and "most popular" rails beside an article do not count
    # against it.
    def secondary_text(root, article_nodes, stats)
      article_keys = article_nodes.map { |node| Dom.key(node) }
      article_ancestor_keys = article_nodes.flat_map { |node| node.ancestors.map { |ancestor| Dom.key(ancestor) } }
      total = 0.0
      stack = root.element_children.to_a
      until stack.empty?
        node = stack.pop
        key = Dom.key(node)
        next if article_keys.include?(key)

        if Dom.signature(node).match?(Patterns::SECONDARY) && !article_ancestor_keys.include?(key)
          total += stats.text_chars(node)
        else
          stack.concat(node.element_children.to_a)
        end
      end
      total
    end
  end
end

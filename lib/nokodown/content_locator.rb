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

    # Sibling sections extend an article whose top candidate holds the share.
    # When only they reach it, they must hold nearly the whole page: page mode
    # would keep every band, and article mode drops the bands they leave out.
    WHOLE_PAGE_SHARE = 0.9

    # Page types whose replies are content: forum threads and Q&A pages.
    DISCUSSIONS = %i[forum qa].freeze

    # Share of a forum page that one comment-named container, or a run of
    # same-named ones, must hold to be the thread itself.
    THREAD_SHARE = 0.25
    THREAD_RUN_SHARE = 0.5

    def initialize(body, page_type: nil)
      @body = body
      @page_type = page_type
    end

    def call
      stats = Stats.new(@body)
      root = main_region(stats) || @body
      mark_thread(root, stats) if @page_type == :forum
      result = Scorer.new(root, stats).call
      article = result && article?(result, root, stats)
      return Selection.new(ArticleHead.new(root, result.nodes, stats).call, :article) if article

      # A thread's posts score alike, so no candidate holds it, and the replies'
      # container alone would leave out the question. Cleaning the whole region
      # as an article still drops per-answer comments, badges and chrome.
      return Selection.new([root], :article) if DISCUSSIONS.include?(@page_type)

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
      required = REQUIRED_SHARE.fetch(@page_type, DEFAULT_SHARE)
      return true if holds_share?(result.core, root, stats, required)
      return false if result.nodes.size == result.core.size

      holds_share?(result.nodes, root, stats, [required, WHOLE_PAGE_SHARE].max)
    end

    def holds_share?(nodes, root, stats, required)
      article_text = nodes.sum { |node| stats.text_chars(node) }
      return false if article_text < MIN_ARTICLE_CHARS

      page_text = stats.text_chars(root) - secondary_text(root, nodes, stats)
      return true if page_text <= 0

      article_text / page_text >= required
    end

    # Comment threads and "most popular" rails beside an article do not count
    # against it. A forum's own thread is not beside it.
    def secondary_text(root, article_nodes, stats)
      article_keys = article_nodes.map { |node| Dom.key(node) }
      article_ancestor_keys = article_nodes.flat_map { |node| node.ancestors.map { |ancestor| Dom.key(ancestor) } }
      total = 0.0
      stack = root.element_children.to_a
      until stack.empty?
        node = stack.pop
        key = Dom.key(node)
        next if article_keys.include?(key) || Dom.thread?(node)

        if Dom.signature(node).match?(Patterns::SECONDARY) && !article_ancestor_keys.include?(key)
          total += stats.text_chars(node)
        else
          stack.concat(node.element_children.to_a)
        end
      end
      total
    end

    # A forum's replies sit in containers named like a comment section: one
    # holding a fair share of the page, or a run of them, one per post. Not on
    # Q&A pages, where the comments under a short question pass the share.
    def mark_thread(root, stats)
      total = stats.text_chars(root)
      regions = outermost_secondary(root)
      thread = regions.select { |node| stats.text_chars(node) >= total * THREAD_SHARE }
      runs = regions.group_by { |node| "#{node.name} #{Dom.signature(node).delete("0-9")}" }.values +
             regions.group_by { |node| "#{node.name} #{Dom.key(node.parent)}" }.values
      runs.each { |run| thread.concat(run) if run.sum { |node| stats.text_chars(node) } >= total * THREAD_RUN_SHARE }
      thread.each { |node| Dom.mark_as_thread(node) }
    end

    def outermost_secondary(root)
      found = []
      stack = root.element_children.to_a
      until stack.empty?
        node = stack.pop
        if Dom.signature(node).match?(Patterns::SECONDARY)
          found << node
        else
          stack.concat(node.element_children.to_a)
        end
      end
      found
    end
  end
end

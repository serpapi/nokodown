# frozen_string_literal: true

module Nokodown
  # Readability's paragraph scoring, run without rewriting the DOM: paragraphs
  # push score up to their ancestors, the best ancestor wins, and siblings that
  # look like part of the same article are merged back in.
  class Scorer
    # core is what Readability merges; nodes adds the sibling sections.
    Result = Struct.new(:top, :nodes, :score, :core)

    SCORED = Set.new(%w[p td pre section h2 h3 h4 h5 h6]).freeze
    PARAGRAPH_MIN = 25
    SECTIONS_SHARE = 0.75
    SECTION_LINK_DENSITY = 0.25
    TOP_CANDIDATES = 5
    # The commas Readability counts, for String#count.
    COMMAS = ",\u060C\uFE50\uFE10\uFE11\u2E41\u2E34\u2E32\uFF0C"

    def self.class_weight(node)
      [node["class"], node["id"]].sum { |value| words_weight(value.to_s.downcase) }
    end

    # Conditional cleaning deletes whatever weighs negative, so it ignores CSS
    # utility tokens and heading anchors ("media" in "h-social-media-tips").
    # Candidate scoring keeps Readability's weight, which some pages need to
    # pick the right candidate.
    # Words matching ignore count for nothing.
    def self.cleaning_weight(node, ignore: nil)
      [node["class"], Dom.name_id(node)].sum do |value|
        tokens = value.to_s.downcase.split.reject { |token| utility_class?(token) }
        tokens = tokens.map { |token| token.gsub(ignore, "") } if ignore
        words_weight(tokens.join(" "))
      end
    end

    # "lg:overflow-hidden" is judged without its variant prefix.
    def self.utility_class?(token)
      token.rpartition(":").last.match?(Patterns::UTILITY_CLASS)
    end

    def self.words_weight(value)
      return 0 if value.empty?

      (value.match?(Patterns::POSITIVE) ? 25 : 0) - (value.match?(Patterns::NEGATIVE) ? 25 : 0)
    end
    private_class_method :utility_class?, :words_weight

    def initialize(root, stats)
      @root = root
      @root_key = Dom.key(root)
      @stats = stats
      @scores = {}
      @nodes = {}
    end

    def call
      @paragraph_keys = Dom.paragraph_keys(@root)
      score_paragraphs
      return if @scores.empty?

      @scores.each_key { |key| @scores[key] *= 1 - @stats.link_density(@nodes[key]) }
      ranked = @scores.keys.max_by(TOP_CANDIDATES) { |key| @scores[key] }.map { |key| @nodes[key] }
      top = climb(shared_ancestor(ranked) || ranked.first)
      core = merge_siblings(top)
      Result.new(top, with_sections(top, core), score(top) || 0.0, core)
    end

    private

    def paragraph?(node)
      @paragraph_keys.include?(Dom.key(node))
    end

    def score(node)
      @scores[Dom.key(node)]
    end

    def score_paragraphs
      ignored = secondary_keys
      @root.traverse do |node|
        next unless node.element?
        next if ignored.include?(Dom.key(node))

        if SCORED.include?(node.name) || paragraph?(node)
          add_score(Dom.text(node), scoring_parent(node))
        elsif node.name == "div"
          phrasing_runs(node).each { |text| add_score(text, node) }
        end
      end
    end

    # Comment threads are prose too, and on news sites they often outscore the
    # article. A thread holding most of the page (a forum) still counts.
    def secondary_keys
      limit = @stats.text_chars(@root) * 0.5
      regions = Dom.elements(@root).select do |node|
        Patterns.secondary?(Dom.signature(node)) && @stats.text_chars(node) < limit
      end
      regions.flat_map { |region| [region] + Dom.elements(region) }.map { |node| Dom.key(node) }.to_set
    end

    # A div wrapping a single paragraph is that paragraph, as far as scoring goes.
    def scoring_parent(node)
      parent = node.parent
      return parent unless node.name == "p" && parent&.name == "div" && parent.element_children.size == 1
      return parent unless parent.children.all? { |child| child.element? || child.content.strip.empty? }

      parent.parent
    end

    # Text sitting directly in a div between block children counts as paragraphs.
    def phrasing_runs(div)
      runs = [+""]
      div.children.each do |child|
        if child.element? && (Dom::PARAGRAPH_BREAKERS.include?(child.name) || Dom.block?(child))
          runs << +""
        else
          runs.last << child.content
        end
      end
      runs.map { |run| Dom.squish(run) }.reject(&:empty?)
    end

    def add_score(text, parent)
      return if text.length < PARAGRAPH_MIN || parent.nil? || !within_root?(parent)

      # Readability counts the pieces between commas; text here is never empty.
      points = 2 + text.count(COMMAS) + [text.length / 100, 3].min
      ancestors_from(parent).each_with_index do |ancestor, level|
        key = Dom.key(ancestor)
        @nodes[key] ||= ancestor
        @scores[key] ||= initial_score(ancestor)
        @scores[key] += points.to_f / divider(level)
      end
    end

    def divider(level)
      case level
      when 0 then 1
      when 1 then 2
      else level * 3
      end
    end

    def ancestors_from(parent)
      list = []
      current = parent
      while current&.element? && list.size < 5
        list << current
        break if Dom.key(current) == @root_key

        current = current.parent
      end
      list
    end

    # A walk up the parents: Node#ancestors builds a NodeSet of every
    # ancestor first, which cost more than the rest of the scoring.
    def within_root?(node)
      while node
        return true if node.element? && Dom.key(node) == @root_key

        node = node.parent
      end
      false
    end

    def initial_score(node)
      self.class.class_weight(node) +
        case node.name
        when "div" then 5
        when "pre", "td", "blockquote" then 3
        when "address", "ol", "ul", "dl", "dd", "dt", "li", "form" then -3
        when "h1", "h2", "h3", "h4", "h5", "h6", "th" then -5
        else 0
        end
    end

    # When several near-equal candidates share an ancestor, the content is
    # split across them: a list of posts, or an article broken up by ads.
    def shared_ancestor(ranked)
      top_score = score(ranked.first)
      return if top_score <= 0

      peers = ranked.drop(1).select { |node| score(node) / top_score >= 0.75 }
      return if peers.size < 3

      peer_ancestor_keys = peers.map { |node| node.ancestors.map { |ancestor| Dom.key(ancestor) } }
      climbable_ancestors(ranked.first).find do |ancestor|
        key = Dom.key(ancestor)
        peer_ancestor_keys.count { |keys| keys.include?(key) } >= 3
      end
    end

    def climbable_ancestors(node)
      node.ancestors.take_while { |ancestor| ancestor.element? && ancestor.name != "body" && within_root?(ancestor) }
    end

    # Readability walks up while the parent scores higher than its child: the
    # content probably continues in the parent's other children.
    def climb(top)
      last = score(top) || 0.0
      threshold = last / 3
      climbable_ancestors(top).each do |parent|
        parent_score = score(parent)
        next unless parent_score
        break if parent_score < threshold

        return single_child_ancestor(parent) if parent_score > last

        last = parent_score
      end
      single_child_ancestor(top)
    end

    def single_child_ancestor(node)
      climbable_ancestors(node).each do |parent|
        break unless parent.element_children.size == 1

        node = parent
      end
      node
    end

    def merge_siblings(top)
      return [top] if standalone?(top)

      top_score = score(top) || 0.0
      threshold = sibling_threshold(top_score)
      top.parent.element_children.select do |sibling|
        sibling == top || related_sibling?(sibling, top, top_score, threshold)
      end
    end

    def standalone?(top)
      Dom.key(top) == @root_key || top.parent.nil?
    end

    def sibling_threshold(top_score)
      [10, top_score * 0.2].max
    end

    def with_sections(top, merged)
      return merged if standalone?(top)

      threshold = sibling_threshold(score(top) || 0.0)
      siblings = top.parent.element_children.to_a
      sections = siblings.select { |sibling| !merged.include?(sibling) && section?(sibling, top, threshold) }
      return merged if sections.sum { |section| @stats.text_chars(section) } < @stats.text_chars(top) * SECTIONS_SHARE

      siblings.select { |sibling| merged.include?(sibling) || sections.include?(sibling) }
    end

    def section?(sibling, top, threshold)
      return false if @stats.link_density(sibling) >= SECTION_LINK_DENSITY

      (!top["class"].to_s.empty? && sibling["class"] == top["class"]) || best_score_within(sibling) >= threshold
    end

    def best_score_within(node)
      best = -Float::INFINITY
      node.traverse do |descendant|
        value = descendant.element? && score(descendant)
        best = value if value && value > best
      end
      best
    end

    def related_sibling?(sibling, top, top_score, threshold)
      same_class = !top["class"].to_s.empty? && sibling["class"] == top["class"]
      sibling_score = score(sibling)
      return true if sibling_score && sibling_score + (same_class ? top_score * 0.2 : 0) >= threshold
      return false unless paragraph?(sibling)

      text = Dom.text(sibling)
      density = @stats.link_density(sibling)
      (text.length > 80 && density < 0.25) || (text.length.between?(1, 80) && density.zero? && text.match?(/\.( |\z)/))
    end
  end
end

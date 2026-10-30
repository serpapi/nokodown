# frozen_string_literal: true

require "set"

module Nokodown
  module Dom
    BLOCK = Set.new(%w[
      address article aside blockquote body caption center dd details dialog dir div dl dt
      fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 header hgroup hr html iframe
      legend li main menu nav ol p pre section summary table tbody td tfoot th thead tr ul
    ]).freeze

    HEADINGS = Set.new(%w[h1 h2 h3 h4 h5 h6]).freeze
    HEADING_SELECTOR = HEADINGS.to_a.join(", ").freeze

    # Elements that stop Readability from treating a div as a paragraph.
    PARAGRAPH_BREAKERS = Set.new(%w[blockquote dl div img ol p pre table ul]).freeze

    # The renderer writes these as code, so their text is never furniture or
    # leaked markup.
    INLINE_CODE = %w[code kbd samp tt].freeze
    CODE = ["pre", *INLINE_CODE].freeze

    INLINE_STYLE = /(?:\A|;)\s*display\s*:\s*inline\s*(?:!important\s*)?(?:;|\z)/i.freeze

    NBSP = "\u00A0"
    WHITESPACE = " \t\n\r\f\u00A0"

    # Every character [[:space:]] matches. tr/squeeze is several times faster
    # than a regex gsub on large subtrees.
    UNICODE_SPACES = "\t\n\v\f\r\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000"

    # Nokolexbor returns a new Ruby object every time a node is read, so nodes
    # cannot be hash keys. Elements get a numbered attribute to key on instead.
    KEY = "data-nokodown-key"

    UUID = /\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/.freeze
    ARBITRARY_VALUE = /\[[^\s\]]*\]/.freeze
    CSS_MODULE_HASH = /__(?=[\w-]{0,4}[A-Z\d])[\w-]{5}(?![\w-])/.freeze
    GRID_CLASS = /\A(?:span|td-pb-span|col-(?:(xs|sm|md|lg|xl|xxl)-)?|(small|medium|large)-)(\d{1,2})\z/.freeze
    BREAKPOINTS = [nil, "xs", "sm", "md", "lg", "xl", "xxl"].freeze
    FOUNDATION = { "small" => "sm", "medium" => "md", "large" => "lg" }.freeze

    # On a forum, the replies sit in containers named like a comment section.
    # ContentLocator marks them and everything inside them, so the mark
    # survives the copy that article cleaning works on.
    THREAD = "data-nokodown-thread"

    # Set by HeadingAnchors on elements whose id is made from their heading.
    ANCHOR = "data-nokodown-anchor"

    # Set by Preprocessor on the wide-screen copy of a block laid out twice.
    WIDE_COPY = "data-nokodown-wide-copy"

    # Broken pages nest thousands of unclosed elements, deeper than the
    # recursive walks after parsing can follow.
    MAX_DEPTH = 256
    UNRENDERED = Set.new(%w[script style template noscript]).freeze
    # Text set straight in these is not in any of their cells or items.
    FRAMES = Set.new(%w[table thead tbody tfoot tr ul ol dl menu dir]).freeze

    module_function

    # Below MAX_DEPTH levels the first element that can hold text keeps
    # only its text, with a space where a block or a line break parted it.
    def flatten_deep(root)
      stack = [[root, 0]]
      until stack.empty?
        node, depth = stack.pop
        children = node.element_children
        if depth < MAX_DEPTH || FRAMES.include?(node.name)
          children.each { |child| stack << [child, depth + 1] }
        elsif !children.empty?
          node.content = flat_text(node)
        end
      end
    end

    def flat_text(node)
      parts = []
      stack = node.children.to_a.reverse
      until stack.empty?
        current = stack.pop
        if current.text?
          parts << current.content
        elsif current.element? && !UNRENDERED.include?(current.name)
          parts << " " if BLOCK.include?(current.name) || current.name == "br"
          stack.concat(current.children.to_a.reverse)
        end
      end
      squish(parts.join)
    end

    def assign_keys(root)
      root[KEY] = "0"
      root.css("*").each_with_index { |node, index| node[KEY] = (index + 1).to_s }
    end

    def key(node)
      node[KEY]
    end

    # The outermost of a node's ancestors below the body that the block
    # accepts, climbing until it refuses one. The links of one line ask about
    # the same ancestors, so verdicts are kept by key.
    def outermost_accepted(node, verdicts)
      found = nil
      node = node.parent
      while node&.element? && node.name != "body"
        key = key(node)
        verdict = key && verdicts.key?(key) ? verdicts[key] : yield(node)
        verdicts[key] = verdict if key
        break unless verdict

        found = node
        node = node.parent
      end
      found
    end

    def mark_as_thread(node)
      node[THREAD] = "1"
      node.css("*").each { |descendant| descendant[THREAD] = "1" }
    end

    def thread?(node)
      !node[THREAD].nil?
    end

    def thread_post?(node)
      thread?(node) && signature(node).match?(Patterns::SECONDARY)
    end

    # Keys of the <p>s and of the divs Readability would rewrite into <p>
    # (no block-level descendants), found in one bottom-up pass.
    def paragraph_keys(root)
      keys = Set.new
      breaks = {}
      root.traverse do |node|
        next unless node.element?

        key = key(node)
        breaks[key] = node.element_children.any? { |child| PARAGRAPH_BREAKERS.include?(child.name) || breaks[key(child)] }
        keys << key if node.name == "p" || (node.name == "div" && !breaks[key])
      end
      keys
    end

    # Nokolexbor answers ancestors(selector) by running CSS matching per
    # ancestor, which dominated extraction time; compare tag names instead.
    def ancestors_named(node, *names)
      node.ancestors.select { |ancestor| ancestor.element? && names.include?(ancestor.name) }
    end

    # Syntax highlighters wrap tokens in spans whose class ("token comment",
    # "tag") or whole text ("print", "email") reads like page furniture.
    def in_code?(node)
      CODE.include?(node.name) || ancestors_named(node, *CODE).any?
    end

    def block?(node)
      node.element? && BLOCK.include?(node.name)
    end

    # DITA and some page builders wrap every phrase in <div style="display:
    # inline">, which flows with the text around it.
    def inline_div?(node)
      node.name == "div" && node["style"].to_s.match?(INLINE_STYLE)
    end

    def heading?(node)
      node.element? && HEADINGS.include?(node.name)
    end

    # A grid column's width in twelfths, from the widest breakpoint its
    # classes name: "col-12 col-md-4" is 4, "td-pb-span8" is 8.
    def grid_width(column)
      widths = column["class"].to_s.split.filter_map do |name|
        match = name.match(GRID_CLASS)
        [BREAKPOINTS.index(match[1] || FOUNDATION[match[2]]), match[3].to_i] if match
      end
      widths.max_by(&:first)&.last
    end

    def char_count(string)
      string.length - string.count(WHITESPACE)
    end

    def text(node)
      squish(node.content)
    end

    def squish(string)
      string.tr(UNICODE_SPACES, " ").squeeze(" ").strip
    end

    def signature(node)
      classes = node["class"]
      id = name_id(node)
      return "" if classes.nil? && id.nil?

      signature_of("#{classes} #{id}")
    end

    # The id as a name for the element; a heading anchor only repeats the heading.
    def name_id(node)
      node.key?(ANCHOR) ? nil : node["id"]
    end

    def signature_of(value)
      # A Tailwind arbitrary value ("lg:h-[calc(100vh-var(--nav-height))]") is CSS, not a name.
      value = value.gsub(ARBITRARY_VALUE, "") if value.include?("[")
      # Generated ids (Webflow "w-node-<uuid>") would otherwise read as words.
      value = value.gsub(UUID, " ") if value.match?(UUID)
      value = value.gsub(CSS_MODULE_HASH, "") if value.include?("__")
      value = value.gsub(/([a-z\d])([A-Z])/, '\1-\2') if value.match?(/[a-z\d][A-Z]/)
      value.downcase
    end

    # Readability's text similarity: share of B's distinct tokens that also occur in A.
    def similarity(a, b)
      tokens_a = tokenize(a)
      tokens_b = tokenize(b)
      return 0.0 if tokens_a.empty? || tokens_b.empty?

      unique_b = tokens_b - tokens_a
      1.0 - (unique_b.join(" ").length.to_f / tokens_b.join(" ").length)
    end

    def tokenize(string)
      string.to_s.downcase.split(/[^\p{L}\p{N}]+/).reject(&:empty?)
    end
  end
end

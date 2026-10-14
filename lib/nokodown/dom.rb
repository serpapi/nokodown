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

    # Elements that stop Readability from treating a div as a paragraph.
    PARAGRAPH_BREAKERS = Set.new(%w[blockquote dl div img ol p pre table ul]).freeze

    NBSP = "\u00A0"
    WHITESPACE = " \t\n\r\f\u00A0"

    # Every character [[:space:]] matches. tr/squeeze is several times faster
    # than a regex gsub on large subtrees.
    UNICODE_SPACES = "\t\n\v\f\r\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000"

    # Nokolexbor returns a new Ruby object every time a node is read, so nodes
    # cannot be hash keys. Elements get a numbered attribute to key on instead.
    KEY = "data-nokodown-key"

    # On a forum, the replies sit in containers named like a comment section.
    # ContentLocator marks them and everything inside them, so the mark
    # survives the copy that article cleaning works on.
    THREAD = "data-nokodown-thread"

    module_function

    def assign_keys(root)
      root[KEY] = "0"
      root.css("*").each_with_index { |node, index| node[KEY] = (index + 1).to_s }
    end

    def key(node)
      node[KEY]
    end

    def mark_as_thread(node)
      node[THREAD] = "1"
      node.css("*").each { |descendant| descendant[THREAD] = "1" }
    end

    def thread?(node)
      !node[THREAD].nil?
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

    def block?(node)
      node.element? && BLOCK.include?(node.name)
    end

    def heading?(node)
      node.element? && HEADINGS.include?(node.name)
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
      id = node["id"]
      return "" if classes.nil? && id.nil?

      value = "#{classes} #{id}"
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

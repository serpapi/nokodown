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
    PARAGRAPH_BREAKER_XPATH = PARAGRAPH_BREAKERS.map { |name| ".//#{name}" }.join("|").freeze

    # The elements the HTML parser reopens after a block cuts them.
    FORMATTING = Set.new(%w[a b big code em font i nobr s small strike strong tt u]).freeze
    FORMATTING_XPATH = FORMATTING.map { |name| ".//#{name}" }.join("|").freeze

    CODE = %w[pre code].freeze

    NBSP = "\u00A0"
    WHITESPACE = " \t\n\r\f\u00A0"

    # Every character [[:space:]] matches. tr/squeeze is several times faster
    # than a regex gsub on large subtrees.
    UNICODE_SPACES = "\t\n\v\f\r\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000"
    ASCII_SPACES = "\t\n\v\f\r"
    # The other characters of UNICODE_SPACES, as UTF-8 bytes.
    NON_ASCII_SPACE_BYTES = Regexp.new(
      "\xC2[\x85\xA0]|\xE1\x9A\x80|\xE2\x80[\x80-\x8A\xA8\xA9\xAF]|\xE2\x81\x9F|\xE3\x80\x80".b, Regexp::NOENCODING
    )
    # What squish can drop: spaces, and a NUL that strip takes off the end.
    ASCII_BLANKS = "#{ASCII_SPACES} \0"
    UNICODE_BLANKS = "#{UNICODE_SPACES} \0"

    # Nokolexbor returns a new Ruby object every time a node is read, so nodes
    # cannot be hash keys. Elements get a numbered attribute to key on instead.
    KEY = "data-nokodown-key"

    UUID = /\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/.freeze
    # A shorter name cannot hold one, so it is not searched.
    UUID_LENGTH = 36
    # One level of brackets may nest ("[&>[data-slot=icon]]"). Possessive, so
    # a run of unclosed "[" is not rescanned from each one.
    ARBITRARY_VALUE = /\[(?:[^\s\[\]]|\[[^\s\[\]]*+\])*+\]/.freeze
    CSS_MODULE_HASH = /__(?=[\w-]{0,4}[A-Z\d])[\w-]{5}(?![\w-])/.freeze
    CAMEL_CASE = /(?<=[a-z\d])(?=[A-Z])/.freeze
    SIGNATURES = :nokodown_signatures
    SECONDARY = :nokodown_secondary
    WEIGHTS = :nokodown_weights

    # On a forum, the replies sit in containers named like a comment section.
    # ContentLocator marks them and everything inside them, so the mark
    # survives the copy that article cleaning works on.
    THREAD = "data-nokodown-thread"

    # Set by HeadingAnchors on elements whose id is made from their heading.
    ANCHOR = "data-nokodown-anchor"

    module_function

    def assign_keys(root)
      root[KEY] = "0"
      elements(root).each_with_index { |node, index| node[KEY] = (index + 1).to_s }
    end

    def key(node)
      node[KEY]
    end

    # The elements under root in document order, as css("*") lists them.
    # Lexbor's selector engine took several times longer to list them
    # than walking the tree from Ruby.
    def elements(root)
      found = []
      stack = []
      child = root.last_element_child
      while child
        stack << child
        child = child.previous_element
      end
      until stack.empty?
        node = stack.pop
        found << node
        child = node.last_element_child
        while child
          stack << child
          child = child.previous_element
        end
      end
      found
    end

    # A node's children, text included, as an Array. Nokolexbor builds a
    # NodeSet and wraps every node again when it is read by index;
    # following the sibling pointers reads each node once.
    def children(node)
      found = []
      child = node.child
      while child
        found << child
        child = child.next_sibling
      end
      found
    end

    # A node's element children as an Array, read through the element
    # pointers like children above.
    def element_children(node)
      found = []
      child = node.first_element_child
      while child
        found << child
        child = child.next_element
      end
      found
    end

    # Root and the elements under it, children before their parent, in the
    # order Node#traverse yields them. Walking the element pointers skips
    # the text nodes and the NodeSet traverse builds for every element.
    def elements_bottom_up(root)
      found = []
      stack = [[root, root.first_element_child]]
      until stack.empty?
        entry = stack.last
        child = entry[1]
        if child
          entry[1] = child.next_element
          stack << [child, child.first_element_child]
        else
          stack.pop
          found << entry[0]
        end
      end
      found
    end

    def mark_as_thread(node)
      node[THREAD] = "1"
      elements(node).each { |descendant| descendant[THREAD] = "1" }
    end

    def thread?(node)
      !node[THREAD].nil?
    end

    def thread_post?(node)
      thread?(node) && secondary?(node)
    end

    # Keys of the <p>s and of the divs Readability would rewrite into <p>
    # (no block-level descendants). Breakers are rare, so marking their
    # ancestors, up to one already marked, is much faster than visiting every
    # node. But Lexbor copies a formatting element that a block cuts
    # (<a><div>…</a>) into elements sharing one attribute list, and so one
    # key, and then which copy holds the block decides. A root with such
    # copies keeps the bottom-up pass, which content selection and cleaning
    # were tuned with: there the copy visited last decides. Both lists are
    # only collected into sets, so XPath, faster than CSS at a list of tag
    # names, finds them in whatever order it returns.
    def paragraph_keys(root)
      return paragraph_keys_bottom_up(root) if shared_keys?(root)

      broken = Set.new
      root.xpath(PARAGRAPH_BREAKER_XPATH).each do |breaker|
        ancestor = breaker.parent
        ancestor = ancestor.parent while ancestor&.element? && broken.add?(key(ancestor))
      end

      candidates = root.xpath(".//p|.//div").to_a
      candidates << root if root.name == "p" || root.name == "div"
      candidates.each_with_object(Set.new) do |node, keys|
        key = key(node)
        keys << key if node.name == "p" || !broken.include?(key)
      end
    end

    def paragraph_keys_bottom_up(root)
      keys = Set.new
      breaks = {}
      elements_bottom_up(root).each do |node|
        key = key(node)
        breaks[key] = element_children(node).any? { |child| PARAGRAPH_BREAKERS.include?(child.name) || breaks[key(child)] }
        keys << key if node.name == "p" || (node.name == "div" && !breaks[key])
      end
      keys
    end

    # XPath, because Lexbor's CSS engine takes several times longer to
    # match a list of tag names.
    def shared_keys?(root)
      keys = root.xpath(FORMATTING_XPATH).map { |node| key(node) }
      keys << key(root) if FORMATTING.include?(root.name)
      keys.uniq.size != keys.size
    end

    # Nokolexbor answers ancestors(selector) by running CSS matching per
    # ancestor, which dominated extraction time, and builds a NodeSet of
    # every ancestor even without one; walk up and compare tag names instead.
    def ancestors_named(node, *names)
      found = []
      ancestor = node.parent
      while ancestor
        found << ancestor if ancestor.element? && names.include?(ancestor.name)
        ancestor = ancestor.parent
      end
      found
    end

    # Syntax highlighters wrap tokens in spans whose class ("token comment",
    # "tag") or whole text ("print", "email") reads like page furniture.
    def in_code?(node)
      CODE.include?(node.name) || ancestors_named(node, *CODE).any?
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

    # The length squish(string) has at least, since squishing keeps every
    # other character. Comparing it with a limit first skips squishing a
    # long subtree only to find it too long.
    def min_text_length(string)
      string.length - string.count(string.ascii_only? ? ASCII_BLANKS : UNICODE_BLANKS)
    end

    def squish(string)
      spaces_to_blanks(string).squeeze(" ").strip
    end

    # Most text is ASCII, where a shorter tr table is twice as fast. Other
    # UTF-8 is changed in its bytes, which takes a third of the time tr
    # takes to read it as characters. No byte of these sequences, nor an
    # ASCII space, occurs inside another character's encoding.
    def spaces_to_blanks(string)
      return string.tr(ASCII_SPACES, " ") if string.ascii_only?
      return string.tr(UNICODE_SPACES, " ") unless string.encoding == Encoding::UTF_8 && string.valid_encoding?

      bytes = string.b
      bytes.gsub!(NON_ASCII_SPACE_BYTES, " ")
      bytes.tr!(ASCII_SPACES, " ")
      bytes.force_encoding(Encoding::UTF_8)
    end

    # The cache is kept by class list, then by id, so a repeated element
    # finds its signature without building the string it is made from.
    def signature(node)
      classes = node["class"]
      id = name_id(node)
      return "" if classes.nil? && id.nil?

      signatures = Thread.current[SIGNATURES]
      return signature_of("#{classes} #{id}") unless signatures

      by_id = signatures[classes] ||= {}
      by_id.fetch(id) { by_id[id] = signature_of("#{classes} #{id}").freeze }
    end

    # Every stage reads the signatures of the same elements again, and a
    # page repeats its class lists, so an extraction computes each one once.
    # The cache lives only as long as the block, so pages share nothing.
    def caching_signatures
      outer = Thread.current[SIGNATURES]
      outer_secondary = Thread.current[SECONDARY]
      outer_weights = Thread.current[WEIGHTS]
      Thread.current[SIGNATURES] = outer || {}
      Thread.current[SECONDARY] = outer_secondary || {}
      Thread.current[WEIGHTS] = outer_weights || {}
      yield
    ensure
      Thread.current[SIGNATURES] = outer
      Thread.current[SECONDARY] = outer_secondary
      Thread.current[WEIGHTS] = outer_weights
    end

    # Whether the element is named like a secondary region. The stages ask
    # it of the same names again, so the answer is kept with the signatures.
    def secondary?(node)
      signature = signature(node)
      answers = Thread.current[SECONDARY]
      return Patterns.secondary?(signature) unless answers

      answers.fetch(signature) { answers[signature] = Patterns.secondary?(signature) }
    end

    # The id as a name for the element; a heading anchor only repeats the heading.
    def name_id(node)
      node.key?(ANCHOR) ? nil : node["id"]
    end

    def signature_of(value)
      # A Tailwind arbitrary value ("lg:h-[calc(100vh-var(--nav-height))]") is CSS, not a name.
      value = value.gsub(ARBITRARY_VALUE, "") if value.include?("[")
      # Generated ids (Webflow "w-node-<uuid>") would otherwise read as words.
      value = value.gsub(UUID, " ") if value.length >= UUID_LENGTH && value.match?(UUID)
      value = value.gsub(CSS_MODULE_HASH, "") if value.include?("__")
      value = value.gsub(CAMEL_CASE, "-") if value.match?(CAMEL_CASE)
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

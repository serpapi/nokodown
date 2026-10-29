# frozen_string_literal: true

require "set"

module Nokodown
  # Text that is markup or a server's error message rather than the page's
  # words: HTML a CMS escaped into alt text or into the page, PHP and Liquid
  # errors printed in place of a template, template placeholders and tags
  # left unrendered, and decoys that a stylesheet hides inside an email
  # address. Code samples are left alone.
  module LeakedMarkup
    CANDIDATE = /[<\[{][a-zA-Z\/]|\{\{|Liquid|on line|@\s/.freeze
    ONLY_TAGS = %r{\A(?:\s*</?[a-z][a-z\d-]*(?:\s[^<>]*)?/?>)+\s*\z}i.freeze
    OPENING_TAG = /<([a-z][a-z\d-]*)/i.freeze
    CLOSING_TAG = %r{</([a-z][a-z\d-]*)}i.freeze
    VOID = Set.new(%w[area base br col embed hr img input link meta param source track wbr]).freeze
    ONLY_PLACEHOLDERS = /\A(?:\s*\{\{[^{}]*\}\})+\s*\z/.freeze
    # Template tags and shortcodes: "{title}", "{article id=34031}",
    # "[link]", "[/link]", "[vc_column_text]". A lone "[1]", "[edit]" or
    # "{Christmas}" is not one.
    BRACE_TAG = '\{/?[a-z][\w.]*(?:\s+[\w-]+=[^{}]*)?\}'
    TEMPLATE_TAG = %r{#{BRACE_TAG}|\[/?[a-z][\w-]*(?:\s+[\w-]+=[^\[\]]*)?\]}.freeze
    SURE_TEMPLATE_TAG = %r{#{BRACE_TAG}|\[/[a-z][\w-]*\]|\[[a-z]+_\w+(?:\s+[\w-]+=[^\[\]]*)?\]}.freeze
    WORD = /[\p{L}\p{N}]/.freeze
    LIQUID_ERROR = /Liquid (?:syntax )?error(?: \([^)]*\))?: .*?(?=Liquid (?:syntax )?error|\z)/m.freeze
    PHP_LEVEL = /\A(?:(?:Catchable |Recoverable )?fatal error|Parse error|Warning|Notice|Deprecated|Strict Standards)\z/i.freeze
    PHP_ERROR = /(?:(?:Catchable |Recoverable )?Fatal error|Parse error|Warning|Notice|Deprecated|Strict Standards): [\s\S]{1,600}? in \S+\.(?:php|inc)\S* on line \d+/.freeze
    LINE_END = /on line\s*\z/.freeze
    MAX_ERROR_NODES = 8
    # "info@ <span>ex.com</span> example.com": no address has spaces.
    DECOY = /\A([^\s@]+@)\s+(\S+)\s+([^\s@]+\.[^\s@]+)\z/.freeze
    LOCAL_PART = /\A\s*[^\s@]+@\s+\z/.freeze

    module_function

    # Addresses are rewritten after the walk over the text: rewriting one
    # frees text nodes the walk has yet to reach. An address holds one "@",
    # so no address contains another.
    def clean(root)
      root.css("img[alt*='<']").each { |img| img["alt"] = Dom.text(root.document.fragment(img["alt"])) }
      root.css("b, strong").each { |bold| drop_php_error(bold) if Dom.text(bold).match?(PHP_LEVEL) }
      addresses = []
      root.xpath(".//text()").each { |text| clean_text(text, addresses) }
      addresses.each { |node| drop_decoy(node) }
    end

    def clean_text(text, addresses)
      content = text.content
      return unless content.match?(CANDIDATE)
      return add_address(text.parent, addresses) if content.match?(LOCAL_PART)

      cleaned = leaked?(content) ? "" : content.gsub(LIQUID_ERROR, "").gsub(PHP_ERROR, "")
      return if cleaned == content || Dom.in_code?(text.parent)

      if cleaned.strip.empty?
        text.remove
      else
        text.content = cleaned
      end
    end

    def leaked?(content)
      closed_tags?(content) || content.match?(ONLY_PLACEHOLDERS) ||
        (content.match?(SURE_TEMPLATE_TAG) && !content.gsub(TEMPLATE_TAG, "").match?(WORD))
    end

    # Elements written out whole ("<abbr id="kygai"></abbr>", an ad's
    # escaped <script>), not a tutorial's lines of markup, which open on
    # one line and close on another.
    def closed_tags?(content)
      return false unless content.match?(ONLY_TAGS)

      closing = content.scan(CLOSING_TAG).flatten.map(&:downcase).reject { |name| VOID.include?(name) }
      opening = content.scan(OPENING_TAG).flatten.map(&:downcase).reject { |name| VOID.include?(name) }
      closing.any? && closing.sort == opening.sort
    end

    # The local part of an address with a decoy is a text node of its own
    # ("info@ "), which a line such as "Lakers @ Celtics" never is.
    def add_address(node, addresses)
      addresses << node unless addresses.last == node || Dom.in_code?(node)
    end

    def drop_decoy(node)
      match = Dom.text(node).match(DECOY)
      return unless match && node.element_children.count { |child| Dom.text(child) == match[2] } == 1

      node.content = match[1] + match[3]
    end

    # PHP prints "<b>Warning</b>: message in <b>/path/file.php</b> on line
    # <b>28</b>", between line breaks, wherever the page was being written.
    def drop_php_error(bold)
      nodes = [bold]
      node = bold.next_sibling
      while node && nodes.size < MAX_ERROR_NODES
        nodes << node
        return nodes.each(&:remove) if line_number?(node, nodes[-2])

        node = node.next_sibling
      end
    end

    def line_number?(node, before)
      node.element? && node.name == "b" && Dom.text(node).match?(/\A\d+\z/) && before.text? && before.content.match?(LINE_END)
    end
  end
end

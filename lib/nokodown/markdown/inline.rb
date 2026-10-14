# frozen_string_literal: true

module Nokodown
  module Markdown
    # Renders a run of inline nodes (text, emphasis, code, links, images) to
    # one string. Line breaks from <br> are kept as "\n".
    class Inline
      EMPHASIS = { "strong" => "**", "b" => "**", "em" => "*", "i" => "*", "del" => "~~", "s" => "~~", "strike" => "~~" }.freeze
      CODE = Set.new(%w[code kbd samp tt]).freeze
      UNSAFE_SCHEME = /\A\s*(?:javascript|vbscript|data|tel|sms):/i.freeze
      FOOTNOTE_MARKER = /\A\s*(?:\[[^\]]{1,8}\]|[*†‡§]+)\s*\z/.freeze
      # Exponents are often written with the minus sign "−", not "-".
      SCRIPT_TEXT = /\A[0-9+\-−=()]+(?:,[0-9+\-−=()]+)*\z/.freeze
      SCRIPT_SOURCE = "0123456789+−=()-"
      SUPERSCRIPTS = "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾⁻"
      SUBSCRIPTS = "₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎₋"
      SCRIPT_WORD = %r{\A[\p{L}\p{N}+\-−=/()]+\z}.freeze
      SCRIPT_OPERATOR = %r{[+\-−=/]}.freeze
      # These have characters of their own: 1º, 30ºC, nº, Acme™.
      RAISED_LETTERS = { "o" => "º", "TM" => "™", "SM" => "℠" }.freeze
      # English and French endings: 21st, 1er, 2nde, XIXe.
      ORDINAL_SUFFIX = /\A(?:st|nd|rd|th|er|ers|re|res|e|es|ème|eme|nde)\z/i.freeze
      NUMBER_END = /(?:\d|\b[IVXLCDM]+)\z/.freeze
      PRICE_END = /\p{Sc}\s?\d[\d,]*\z/.freeze
      CENTS = /\A\d\d\z/.freeze
      ATTACHED = /[\p{L}\p{N})\]]\z/.freeze

      def initialize(urls, images:, links:)
        @urls = urls
        @images = images
        @links = links
        @emphasis = Hash.new(0)
        @in_heading = false
        @in_link = false
        @link_images = nil
      end

      def render(nodes, heading: false)
        outer = @in_heading
        @in_heading ||= heading
        nodes.map { |node| node_text(node) }.join
      ensure
        @in_heading = outer
      end

      # Absolute URL worth linking to, or nil for in-page anchors, scripts and
      # phone numbers.
      def link_url(href)
        href = href.strip
        return if href.empty? || href.start_with?("#") || href.match?(UNSAFE_SCHEME)

        url = @urls.resolve(href)
        url unless url.nil? || @urls.same_page?(url)
      end

      private

      def node_text(node)
        if node.text? || node.cdata?
          Text.escape(Text.collapse(node.content))
        elsif node.element?
          element_text(node)
        else
          ""
        end
      end

      def element_text(node)
        name = node.name
        return emphasis(node, EMPHASIS[name]) if EMPHASIS.key?(name)
        return code_span(node) if CODE.include?(name)

        case name
        when "br" then "\n"
        when "wbr" then ""
        when "a" then link(node)
        when "img" then image(node)
        when "q" then "\"#{render(node.children)}\""
        when "math" then math(node)
        when "sup", "sub" then script(node)
        when "input" then node.key?("checked") ? "[x] " : "[ ] "
        else
          text = render(node.children)
          Dom::BLOCK.include?(name) ? " #{text} " : text
        end
      end

      # Headings are bold already; nested emphasis of the same kind is dropped.
      def emphasis(node, marker)
        return render(node.children) if @emphasis[marker].positive? || (@in_heading && marker == "**")

        @emphasis[marker] += 1
        content = render(node.children)
        @emphasis[marker] -= 1
        core = content.strip
        return content if core.empty? || core.match?(/\A[^\p{L}\p{N}]*\z/)

        "#{content[/\A\s*/]}#{marker}#{core}#{marker}#{content[/\s*\z/]}"
      end

      def code_span(node)
        text = Text.collapse(node.content)
        core = text.strip
        return text.empty? ? "" : " " if core.empty?

        "#{text[/\A\s*/]}#{Text.code_span(core)}#{text[/\s*\z/]}"
      end

      # Images inside a link are written before it rather than inside its text.
      def link(node)
        outer_images = @link_images
        outer_link = @in_link
        @link_images = []
        @in_link = true
        content = render(node.children)
        images = @link_images
        @link_images = outer_images
        @in_link = outer_link

        parts = images + [link_markup(Text.single_line(content), node["href"].to_s)]
        surround_like(content, parts.reject(&:empty?).join(" "))
      end

      def link_markup(text, href)
        return "" if text.empty? || text.match?(Patterns::LINK_NOISE_TEXT)
        return text if !@links || @in_link

        url = link_url(href)
        return text unless url
        return url if same_as_url?(text, url)

        "[#{Text.link_text(text)}](#{Text.destination(url)})"
      end

      def same_as_url?(text, url)
        bare(text.delete("\\")) == bare(url)
      end

      def bare(url)
        url.sub(%r{\Ahttps?://}i, "").sub(/\Awww\./i, "").sub(/\Amailto:/i, "").chomp("/")
      end

      def surround_like(original, rendered)
        return rendered if rendered.empty?

        leading = original.match?(/\A\s/) ? " " : ""
        trailing = original.match?(/\s\z/) ? " " : ""
        "#{leading}#{rendered}#{trailing}"
      end

      def image(node)
        alt = Dom.squish(node["alt"].to_s)
        return Image.tex(alt) if node["class"].to_s.include?("mwe-math-fallback-image")
        return alt if Image.emoji?(node, alt)
        return "" if !@images || @in_heading

        src = Image.source(node, @urls)
        return "" if src.nil? || Image.decorative?(node, src, alt)

        markup = "![#{Text.link_text(Text.escape(alt))}](#{Text.destination(src)})"
        return markup unless @link_images

        @link_images << markup
        ""
      end

      # Markdown has no superscript, and "2attempt" is wrong. Digits and signs
      # have Unicode forms (10⁶, H₂O); other raised and lowered words get a
      # caret or an underscore (x^n, a_n). Footnote markers such as [1],
      # symbols such as ® and small print read fine as plain text.
      def script(node)
        text = render(node.children)
        core = text.strip
        return text if core.empty? || text.match?(FOOTNOTE_MARKER) || node.at_css("a")

        previous = previous_node(node)
        before = previous&.content.to_s
        marked = node.name == "sup" ? superscript(core, previous, before) : subscript(core, before)
        marked || text
      end

      # The node right before this one, looking past inline wrappers that it
      # opens (21<span><sup>st</sup></span>).
      def previous_node(node)
        node = node.parent while node.previous_sibling.nil? && inline_parent?(node)
        node.previous_sibling
      end

      def inline_parent?(node)
        parent = node.parent
        parent&.element? && !Dom::BLOCK.include?(parent.name)
      end

      # Cents and ordinals are raised only for looks: $549.99, 21st, XIXe.
      def superscript(core, previous, before)
        return ".#{core}" if core.match?(CENTS) && price_before?(previous, before)
        return core.tr(SCRIPT_SOURCE, SUPERSCRIPTS) if core.match?(SCRIPT_TEXT)
        return RAISED_LETTERS[core] if RAISED_LETTERS.key?(core)
        return if core.match?(ORDINAL_SUFFIX) && before.match?(NUMBER_END)

        "^#{grouped(core)}" if expression?(core)
      end

      # A lowered word is an index only when it hangs off the word before it.
      def subscript(core, before)
        return core.tr(SCRIPT_SOURCE, SUBSCRIPTS) if core.match?(SCRIPT_TEXT)

        "_#{grouped(core)}" if expression?(core) && before.match?(ATTACHED)
      end

      # $549<sup>99</sup> and <sup>$</sup>549<sup>99</sup>.
      def price_before?(previous, before)
        before = "#{previous.previous_sibling&.content}#{before}" if before.match?(/\A[\d,]+\z/)
        before.match?(PRICE_END)
      end

      # Spaces count only around operators (n - 1), so small print is not an
      # expression.
      def expression?(core)
        compact = core.delete(" ")
        compact.match?(SCRIPT_WORD) && (compact == core || compact.match?(SCRIPT_OPERATOR))
      end

      # 2^n-1 would read as 2^n minus 1, and 2^2n as 2^2 times n.
      def grouped(core)
        return core if core.length == 1 || core.match?(/\A\p{L}+\z/) || core.match?(/\A\(.*\)\z/)

        "(#{core})"
      end

      def math(node)
        annotation = node.css("annotation").find { |a| a["encoding"].to_s.include?("tex") }
        tex = (annotation&.content || node["alttext"]).to_s.strip
        return Text.escape(Text.collapse(node.content).strip) if tex.empty?

        node["display"] == "block" ? "$$#{tex}$$" : "$#{tex}$"
      end
    end
  end
end

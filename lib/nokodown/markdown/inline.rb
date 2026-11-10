# frozen_string_literal: true

module Nokodown
  module Markdown
    RenderedImage = Struct.new(:url, :redundant, :targets)

    # Renders a run of inline nodes (text, emphasis, code, links, images) to
    # one string. Line breaks from <br> are kept as "\n".
    class Inline
      EMPHASIS = { "strong" => "**", "b" => "**", "em" => "*", "i" => "*", "del" => "~~", "s" => "~~", "strike" => "~~" }.freeze
      CODE = Set.new(%w[code kbd samp tt]).freeze
      # What could start a link, an autolink, HTML or code where a URL is
      # written as text.
      MARKUP_IN_URL = /[\[\]<>`\\]/.freeze
      UNSAFE_SCHEME = /\A\s*(?:javascript|vbscript|data|tel|sms):/i.freeze
      FOOTNOTE_MARKER = /\A\s*(?:\[[^\]]{1,8}\]|[*†‡§]+)\s*\z/.freeze
      # Exponents are often written with the minus sign "−", not "-".
      SCRIPT_TEXT = /\A[0-9+\-−=()]+(?:,[0-9+\-−=()]+)*\z/.freeze
      SCRIPT_SOURCE = "0123456789+−=()-"
      SUPERSCRIPTS = "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾⁻"
      SUBSCRIPTS = "₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎₋"
      # A point or a comma only between digits or letters: 10^(2.5), a_(i,j).
      SCRIPT_WORD = %r{\A(?:[\p{L}\p{N}+\-−=/()]|(?<=[\p{L}\p{N}])[.,](?=[\p{L}\p{N}]))+\z}.freeze
      SCRIPT_OPERATOR = %r{[+\-−=/]}.freeze
      GROUPED = /\A(\((?:[^()]|\g<1>)*\))\z/.freeze
      # These have characters of their own (1º, nº, Acme™); a raised o before
      # C or F is a degree (30°C).
      RAISED_LETTERS = { "o" => "º", "TM" => "™", "SM" => "℠" }.freeze
      DEGREE_UNIT = /\A\s?[CF]\b/.freeze
      # English and French endings: 21st, 1er, 2nde, XIXe.
      ORDINAL_SUFFIX = /\A(?:st|nd|rd|th|er|ers|re|res|e|es|ème|eme|nde|a|as|os|ª|do|da|ra|ro|ta|to)\z/i.freeze
      NUMBER_END = /(?:\d|\b[IVXLCDM]+)\z/.freeze
      # French titles: Mme, Mlle, Mgr.
      TITLE_SUFFIX = /\A(?:me|mes|lle|lles|gr)\z/.freeze
      PRICE_END = /(?:\p{Sc}|\b[A-Z]{3})\s?\d[\d,.]*\z/.freeze
      DOT_GROUPED = /\d\.\d{3}\z/.freeze
      MATH_BASE = /(?:\d|(?<![\p{L}\p{N}])\p{L})\z/.freeze
      PRICE_START = /\A\s?\p{Sc}/.freeze
      CENTS = /\A\d\d\z/.freeze
      ATTACHED = /[\p{L}\p{N})\]]\z/.freeze
      WORD_START = /\A[\p{L}\p{N}]/.freeze
      WORD_END = /[\p{L}\p{N}]\z/.freeze

      # Absolute URL worth linking to, or nil for in-page anchors, scripts and
      # phone numbers.
      def self.link_url(href, urls)
        href = UrlResolver.normalize(href)
        return if href.empty? || href.start_with?("#") || href.match?(UNSAFE_SCHEME)

        url = urls.resolve(href)
        url unless url.nil? || urls.same_page?(url)
      end

      # redundant_images: RedundantImages#call.
      def initialize(urls, images:, links:, redundant_images: {})
        @urls = urls
        @images = images
        @links = links
        @redundant_images = redundant_images
        @rendered_images = {}
        @emphasis = Hash.new(0)
        @in_heading = false
        @in_link = false
        @link_images = nil
      end

      # Markup of every image written, for Cleanup to drop redundant images
      # and repeats.
      attr_reader :rendered_images

      def render(nodes, heading: false)
        outer = @in_heading
        @in_heading ||= heading
        nodes.map { |node| node_text(node) }.join
      ensure
        @in_heading = outer
      end

      def link_url(href)
        Inline.link_url(href, @urls)
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
        when "video", "audio" then media(node)
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
        return url if same_as_url?(text, url) && !url.match?(MARKUP_IN_URL)

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
        return Text.escape(alt) if Image.emoji?(node, alt)
        return "" if !@images || @in_heading

        src = Image.source(node, @urls)
        return "" if src.nil? || Image.decorative?(node, src, alt)

        markup = "![#{Text.link_text(Text.escape(alt))}](#{Text.destination(src)})"
        record(markup, src, node)
        return markup unless @link_images

        @link_images << markup
        ""
      end

      # Players link to the file they play, labelled with their title, which
      # is escaped like any text.
      def media(node)
        url = link_url(node["src"].to_s)
        return "" if url.nil? || !@links || @in_link

        title = Dom.squish(node["title"].to_s)
        "[#{title.empty? ? node.name.capitalize : Text.label(title)}](#{Text.destination(url)})"
      end

      # An image is redundant only if every copy of it is. Targets are the
      # pages whose text links make its thumbnail copies redundant.
      def record(markup, src, node)
        image = (@rendered_images[markup] ||= RenderedImage.new(src, true, Set.new))
        key = Dom.key(node)
        image.redundant &&= @redundant_images.key?(key)
        target = @redundant_images[key]
        image.targets << target if target
      end

      # Markdown has no superscript, and "2attempt" is wrong. Digits and signs
      # have Unicode forms (10⁶, H₂O); other raised and lowered words get a
      # caret or an underscore (x^n, a_n). Footnote markers such as [1],
      # symbols such as ® and small print read fine as plain text. The plain
      # text decides, so 2<sup><i>p</i></sup> is 2^p like 2<sup>p</sup>.
      def script(node)
        text = render(node.children)
        core = Text.collapse(node.content).strip
        return text if core.empty? || core.match?(FOOTNOTE_MARKER) || node.at_css("a, img, math")

        before = text_before(node) + text[/\A\s*/]
        after = text[/\s*\z/] + adjacent(node, :next_sibling)&.content.to_s
        return nested_script(node, text, core, before, after) if node.at_css("sup, sub")

        marked = node.name == "sup" ? superscript(core, before, after, text_before(node, skip_blank: true)) : subscript(node, core, before, after)
        marked ? surround_like(text, marked) : unmarked(text, core, before, after)
      end

      def nested_script(node, text, core, before, after)
        return unmarked(text, core, before, after) unless before.match?(MATH_BASE)

        surround_like(text, "#{node.name == 'sup' ? '^' : subscript_mark(node, before)}(#{text.strip})")
      end

      # Glued on, a raised or lowered word would merge with the words around
      # it: Smitha, b for Smith<sup>a, b</sup>, aNote for <sup>a</sup>Note.
      def unmarked(text, core, before, after)
        leading = before.match?(ATTACHED) && core.match?(WORD_START) ? " " : ""
        trailing = core.match?(WORD_END) && after.match?(WORD_START) ? " " : ""
        "#{leading}#{text}#{trailing}"
      end

      # Text of the node before, with the one before that when it is a bare
      # amount (<sup>$</sup>549<sup>99</sup>).
      def text_before(node, skip_blank: false)
        previous = adjacent(node, :previous_sibling)
        previous = filled(previous) if skip_blank
        before = previous&.content.to_s
        return before unless before.match?(/\A[\d,.]+\z/)

        earlier = previous.previous_sibling
        earlier = filled(earlier) if skip_blank
        "#{earlier&.content}#{before}"
      end

      def filled(node)
        node = node.previous_sibling while node&.text? && node.content.strip.empty? && node.previous_sibling
        node
      end

      # The node right before or after this one, looking past inline wrappers
      # that it opens or closes (21<span><sup>st</sup></span>).
      def adjacent(node, direction)
        node = node.parent while node.public_send(direction).nil? && inline_parent?(node)
        node.public_send(direction)
      end

      def inline_parent?(node)
        parent = node.parent
        parent&.element? && !Dom::BLOCK.include?(parent.name)
      end

      # Cents and ordinals are raised only for looks: $549.99, 21st, XIXe. A
      # badge after a space (Feature <sup>NEW</sup>) is not an exponent.
      def superscript(core, before, after, amount)
        return cents(core, amount) if core.match?(CENTS) && price?(amount, after)
        return core.tr(SCRIPT_SOURCE, SUPERSCRIPTS) if core.match?(SCRIPT_TEXT)
        return core if plain_suffix?(core, before)

        raised_letter(core, after) || ("^#{grouped(core, after)}" if expression?(core) && math_base?(core, before))
      end

      def math_base?(core, before)
        before.match?(MATH_BASE) || (before.match?(/\)\z/) && core.match?(/[\d+\-−=\/]/))
      end

      # A lowered word is an index only when it hangs off the word before it.
      def subscript(node, core, before, after)
        return core.tr(SCRIPT_SOURCE, SUBSCRIPTS) if core.match?(SCRIPT_TEXT)

        return unless expression?(core) && before.match?(ATTACHED)

        "#{subscript_mark(node, before)}#{grouped(core, after)}"
      end

      def subscript_mark(node, before)
        previous = adjacent(node, :previous_sibling)
        marked = previous&.element? && (EMPHASIS.key?(previous.name) || CODE.include?(previous.name))
        before.match?(WORD_END) && !marked ? "_" : "\\_"
      end

      # $549<sup>99</sup>, <sup>$</sup>549<sup>99</sup> and 549<sup>99</sup> €.
      def price?(before, after)
        before.match?(PRICE_END) || (before.match?(/\d,?\z/) && after.match?(PRICE_START))
      end

      # €12,<sup>99</sup> has its decimal comma already.
      def cents(core, before)
        return core if before.end_with?(",")

        before.match?(DOT_GROUPED) ? ",#{core}" : ".#{core}"
      end

      def plain_suffix?(core, before)
        (core.match?(ORDINAL_SUFFIX) && before.match?(NUMBER_END)) || (core.match?(TITLE_SUFFIX) && before.match?(/\bM\z/))
      end

      def raised_letter(core, after)
        return "°" if core == "o" && after.match?(DEGREE_UNIT)

        RAISED_LETTERS[core] || RAISED_LETTERS[core.upcase]
      end

      # Spaces count only around operators (n - 1), so small print is not an
      # expression.
      def expression?(core)
        compact = core.delete(" ")
        compact.match?(SCRIPT_WORD) && (compact == core || compact.match?(SCRIPT_OPERATOR))
      end

      # 2^n-1 would read as 2^n minus 1, 2^2n as 2^2 times n, e^(a)(b) as
      # e^(a) times (b), and x_iy_i as x with the index iy_i.
      def grouped(core, after)
        return core if core.match?(GROUPED)
        return core if (core.length == 1 || core.match?(/\A\p{L}+\z/)) && !after.match?(WORD_START)

        "(#{core})"
      end

      def math(node)
        annotation = node.css("annotation").find { |a| a["encoding"].to_s.include?("tex") }
        tex = (annotation&.content || node["alttext"]).to_s.strip
        return Text.escape(Text.collapse(node.content).strip) if tex.empty?

        tex = Text.tex(tex)
        node["display"] == "block" ? "$$#{tex}$$" : "$#{tex}$"
      end
    end
  end
end

# frozen_string_literal: true

module Nokodown
  module Markdown
    RenderedImage = Struct.new(:url, :redundant, :targets)

    # Renders a run of inline nodes (text, emphasis, code, links, images) to
    # one string. Line breaks from <br> are kept as "\n".
    class Inline
      EMPHASIS = { "strong" => "**", "b" => "**", "em" => "*", "i" => "*", "del" => "~~", "s" => "~~", "strike" => "~~" }.freeze
      CODE = Set.new(%w[code kbd samp tt]).freeze
      UNSAFE_SCHEME = /\A\s*(?:javascript|vbscript|data|tel|sms):/i.freeze
      FOOTNOTE_MARKER = /\A\s*(?:\[[^\]]{1,8}\]|[*†‡§]+)\s*\z/.freeze

      # Absolute URL worth linking to, or nil for in-page anchors, scripts and
      # phone numbers.
      def self.link_url(href, urls)
        href = href.strip
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
        record(markup, src, node)
        return markup unless @link_images

        @link_images << markup
        ""
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

      # Markdown has no superscript, and "2attempt" is wrong; footnote markers
      # such as [1] read fine without the tag.
      def script(node)
        text = render(node.children)
        return text if text.strip.empty? || text.match?(FOOTNOTE_MARKER) || node.at_css("a")

        "<#{node.name}>#{text.strip}</#{node.name}>"
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

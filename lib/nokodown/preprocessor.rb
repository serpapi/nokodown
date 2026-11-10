# frozen_string_literal: true

require "json"

module Nokodown
  # Removes everything that can never be content: scripts, invisible elements,
  # form controls, embeds. Lazy-loaded images are restored first so their
  # placeholders are not mistaken for decoration.
  class Preprocessor
    JUNK = %w[
      script style noscript template link meta base object embed applet param canvas map area svg
      source track select option optgroup datalist progress meter keygen frame frameset portal slot
    ].join(",").freeze
    # Visible text that is not content, but is when a whole page, or a
    # selection of it, is converted; a closed dialog is never visible.
    CONTROLS = "dialog, textarea, output"
    FULL_CONTROLS = "dialog:not([open])"

    HIDDEN_CLASSES = Set.new(%w[
      hidden hide d-none is-hidden u-hidden visually-hidden visuallyhidden sr-only screen-reader-text
      screen-reader-only screenreader-only a11y-hidden offscreen invisible element-invisible
      print-only visible-print d-print-block show-for-sr w-condition-invisible
    ]).freeze

    # Found by Lexbor's selector engine, so the checks below only run on
    # elements that could be hidden.
    HIDDEN_CANDIDATES = (["[hidden]", "[aria-hidden=true]", "[style]"] + HIDDEN_CLASSES.map { |name| ".#{name}" }).join(", ").freeze

    # Utility classes that make a "hidden" element visible again at some breakpoint.
    RESPONSIVE_SHOW = /\A(?:(?:sm|md|lg|xl|2xl):(?:block|flex|grid|inline|inline-block|inline-flex|table|contents)|d-(?:sm|md|lg|xl|xxl)-(?:block|flex|grid|inline|inline-block|inline-flex|table))\z/.freeze

    STREAMED_LINK_SHARE = 0.5
    SUSPENSE_OPEN = %w[$ $? $!].freeze
    # The site's home page, maybe for one language ("/en/").
    HOME_LINK = %r{\A(?:(?:https?:)?//[^/?#]+)?(?:/(?:[a-z]{2}(?:[-_][a-z]{2})?/?)?(?:index\.\w+)?)?\z}i.freeze

    HIDDEN_STYLE = /(?:\A|;)\s*(?:display\s*:\s*none|visibility\s*:\s*hidden)/i.freeze

    LINE_NUMBERS = /(?<![a-z])(?:line-?numbers?(?:-rows)?|linenos?|lineno|gutter|hljs-ln-numbers|ln-num)(?![a-z])/.freeze

    # A player page on a video host: an http(s) or scheme-relative URL whose
    # host is the provider's and which has a path, not a mention of the host
    # anywhere in another URL ("mailto:x//player.vimeo.com/…").
    VIDEO_HOSTS = %r{\A(?:https?:)?//(?:www\.)?(?:(?:(?:dailymotion|youtube|youtube-nocookie|player\.vimeo|v\.qq|bilibili|live\.bilibili)\.com|
                     (?:archive|upload\.wikimedia)\.org|player\.twitch\.tv|fast\.wistia\.(?:net|com)|play\.vidyard\.com)(?::\d+)?/[^/?#\s]|
                     loom\.com/embed/)}ix.freeze

    IMAGE_URL = /\.(?:jpe?g|png|webp|gif|avif)(?:[?#]\S*)?\s*\z/i.freeze
    IMAGE_SRCSET = /\.(?:jpe?g|png|webp|gif|avif)(?:\?\S*)?\s+\d/i.freeze
    # Where lazy loaders keep the real image, high-resolution names first,
    # then other loaders' names.
    LAZY_SRC = %w[
      data-a-hires data-src-hq data-client-src-hq data-original data-full-src data-original-src data-src
      data-lazy-src data-lazy data-lazysrc data-bsrc data-iurl data-thumb data-image data-img
      data-a-image-source data-fallback-src data-hi-res-src data-large-src data-orig-src data-actualsrc
      data-url data-echo data-img-src
    ].freeze
    # All but the generic names that hold an image only on an image marked
    # as lazy; on others they are links or IDs.
    LAZY_ONLY_SRC = (LAZY_SRC - %w[data-url data-echo data-img-src]).freeze
    LAZY_SRCSET = %w[data-srcset data-lazy-srcset data-original-set].freeze
    # What a template writes for a missing value.
    NO_VALUE = /\A(?:false|true|null|nil|none|undefined|NaN)\z/i.freeze

    # Where script-driven links keep their target when they have no href.
    LINK_TARGETS = %w[data-href data-url data-target-url data-delayed-url data-fallback-url ourl rl-link-href].freeze

    # Below this many levels under <body>, elements become plain text. Page
    # analysis and rendering recurse once per level, and a thread's stack
    # (Puma serves requests in threads) runs out after a few hundred; real
    # pages nest about 20 levels deep, rarely more than 50.
    MAX_DEPTH = 64

    # Elements whose renderer reads only certain children, and the wrapper
    # their flattened text needs so it is not dropped.
    TEXT_WRAPPERS = {
      "table" => %w[tr td], "thead" => %w[tr td], "tbody" => %w[tr td], "tfoot" => %w[tr td],
      "tr" => %w[td], "dl" => %w[dd]
    }.freeze

    def self.video_embed?(src)
      UrlResolver.normalize(src).match?(VIDEO_HOSTS)
    end

    # full: the whole page, or a selection of it, is converted, so only what
    # a reader cannot see goes; forms, buttons, labels and open dialogs stay.
    def initialize(body, full: false)
      @body = body
      @full = full
    end

    def call
      place_streamed_segments
      @body.xpath(".//comment()").each(&:remove)
      unwrap_noscript
      @body.css("img").each { |img| restore_lazy_image(img) }
      restore_picture_sources
      @body.css("a").each { |link| restore_link_target(link) if UrlResolver.normalize(link["href"]).empty? }
      @body.css("video, audio").each { |media| keep_playable(media) }
      @body.css(JUNK).each(&:remove)
      @body.css(@full ? FULL_CONTROLS : CONTROLS).each(&:remove)
      @body.css("iframe").each { |iframe| iframe.remove unless Preprocessor.video_embed?(iframe["src"]) }
      @body.css("pre [class], table[class] td[class]").each { |node| node.remove if node["class"].downcase.match?(LINE_NUMBERS) }
      remove_hidden
      remove_form_controls
      flatten_deep_elements
      HeadingAnchors.mark(@body)
      Dom.assign_keys(@body)
    end

    private

    # Slots are found by id in a hash: an id put into a selector can break it
    # ("S:1']"). A slot inside a fallback removed for an earlier segment is gone.
    def place_streamed_segments
      segments = @body.css("div[hidden][id^='S:']")
      return if segments.empty?

      slots = Hash.new { |hash, number| hash[number] = [] }
      @body.css("template[id^='B:'], template[id^='P:']").each { |template| slots[template["id"][2..]] << template }
      segments.each do |segment|
        slot = slots[segment["id"].delete_prefix("S:")].find { |template| template.ancestors.include?(@body) }
        next if slot.nil? || link_list?(segment)

        remove_fallback(slot) if slot["id"].start_with?("B:")
        slot.replace(segment.children)
        segment.remove
      end
    end

    # What a page streams last waits on another service, and on shops and
    # news sites that is mostly carousels of recommended products and stories.
    # Made of links, such a segment stays hidden, as it is without scripts.
    def link_list?(segment)
      text = visible_char_count(segment)
      links = segment.css("a[href]").sum { |link| Dom.char_count(link.content) }
      text.positive? && links >= text * STREAMED_LINK_SHARE
    end

    # The fallback runs to the comment that closes the boundary, past any
    # boundaries nested in it ("$", "$?" or "$!" open one, "/$" closes it).
    def remove_fallback(slot)
      fallback = []
      depth = 0
      node = slot.next_sibling
      until node.nil?
        if node.comment? && SUSPENSE_OPEN.include?(node.content)
          depth += 1
        elsif node.comment? && node.content == "/$"
          break if depth.zero?

          depth -= 1
        end
        fallback << node
        node = node.next_sibling
      end
      fallback.each(&:remove) if node
    end

    # Lexbor keeps <noscript> content as text. Lazy loaders put the real <img>
    # there, and some apps (Discourse) put the whole page there for crawlers.
    def unwrap_noscript
      @body.css("noscript").each do |noscript|
        fragment = @body.document.fragment(noscript.content)
        images = fragment.css("img")
        if images.size == 1 && Dom.text(fragment).empty?
          (lazy_copy(noscript, images.first) || noscript).replace(images.first)
        elsif Dom.char_count(fragment.content) >= 300 && empty_without_noscript?
          noscript.replace(fragment.children)
        end
      end
    end

    def empty_without_noscript?
      @empty_without_noscript = visible_char_count < 200 if @empty_without_noscript.nil?
      @empty_without_noscript
    end

    def visible_char_count(root = @body)
      invisible = root.css("script, style, noscript, template").sum { |node| Dom.char_count(node.content) }
      Dom.char_count(root.content) - invisible
    end

    # The lazy copy sits just before the <noscript>, or just after it when it
    # loads the same file. Otherwise both copies would be rendered.
    def lazy_copy(noscript, image)
      following = lone_image(noscript.next_element)
      return following if following && same_source?(following, image)

      lone_image(noscript.previous_element)
    end

    def lone_image(node)
      return unless node
      return node if node.name == "img"

      images = node.css("img")
      images.first if images.size == 1 && Dom.text(node).empty?
    end

    def same_source?(img, image)
      src = image["src"].to_s.strip
      !src.empty? && ["src", *LAZY_SRC].any? { |name| img[name].to_s.strip == src }
    end

    # Loaders mark their images with a "lazy" class or with nothing but the
    # attribute, so the attributes win over any src: a spacer, a
    # placeholder or a low-quality thumbnail. Amazon lists its sizes in
    # data-a-dynamic-image, of which the largest wins. A lazy srcset
    # gives its largest image, after the plain attributes.
    def restore_lazy_image(img)
      dynamic = dynamic_image(img["data-a-dynamic-image"])
      return img["src"] = dynamic if dynamic

      img.remove_attribute("src") if placeholder_src?(img)
      marked = img["src"].to_s.strip.empty? || img["class"].to_s.downcase.include?("lazy")
      source = lazy_source(img, marked ? LAZY_SRC : LAZY_ONLY_SRC, marked: marked) || lazy_srcset_source(img, marked)
      img["src"] = source if source
      restore_from_any_attribute(img) if marked && img["src"].to_s.strip.empty? && !img["srcset"]
    end

    # The largest of the image URLs mapped to [width, height].
    def dynamic_image(value)
      return unless value.to_s.lstrip.start_with?("{")

      sizes = JSON.parse(value)
      return unless sizes.is_a?(Hash)

      urls = sizes.select { |url, _| lazy_candidate?(url.strip) }
      urls.max_by { |_, size| size.is_a?(Array) && size[0].is_a?(Numeric) && size[1].is_a?(Numeric) ? size[0] * size[1] : 0 }&.first&.strip
    rescue JSON::ParserError
      nil
    end

    # The first of the attributes that holds an image location, as opposed
    # to "false", an ID, a fragment, a template, another scheme or a spacer
    # file. On a marked image any path, file name or query counts, spaces
    # and all, as a loader may serve images from any relative URL. Without
    # a src to fall back on (none, or an empty one), so does a bare word
    # ("portrait"), in attribute order. An unmarked image's src is replaced
    # only by a path, a query or a file name.
    def lazy_source(img, names, marked:)
      values = names.map { |name| img[name].to_s.strip }.select { |value| lazy_candidate?(value) }
      return values.find { |value| image_location?(value) } unless marked
      return values.find { |value| !value.match?(NO_VALUE) } if img["src"].to_s.strip.empty?

      values.find { |value| value.match?(%r{[/.?]}) }
    end

    def lazy_srcset_source(img, marked)
      LAZY_SRCSET.each do |name|
        url = Markdown::Image.largest_srcset(img[name].to_s.strip).to_s.strip
        return url if lazy_candidate?(url) && (marked || image_location?(url))
      end
      nil
    end

    def lazy_candidate?(value)
      return false if value.empty? || value.start_with?("#") || value.match?(/[{}<>]/)
      return false if value.match?(/\A[a-z][a-z\d+.-]*:/i) && !value.match?(%r{\Ahttps?://}i)

      !value.match?(Markdown::Image::TRACKING)
    end

    # A path, a query or a file name with an extension, without spaces: not
    # a word ("Facebook", "X (formerly Twitter)"), an ID or a number ("1.5").
    def image_location?(value)
      !value.match?(/\s/) && value.match?(%r{[/?]|\.[a-z][a-z\d]{1,4}(?:[?#]|\z)}i)
    end

    def restore_from_any_attribute(img)
      img.attribute_nodes.each do |attribute|
        next if %w[src srcset alt].include?(attribute.name)

        value = attribute.value.to_s
        if value.match?(IMAGE_SRCSET)
          img["srcset"] = value
        elsif value.match?(IMAGE_URL) && !value.include?(" ")
          img["src"] = value
        end
      end
    end

    # Tiny base64 GIF/PNG stand-ins that a lazy loader swaps out, and
    # spacer and placeholder files.
    def placeholder_src?(img)
      src = img["src"].to_s.strip
      return src.match?(Markdown::Image::TRACKING) unless src.start_with?("data:")
      return false if src.start_with?("data:image/svg+xml") && src.length > 200

      src.length < 300 || img.attribute_nodes.any? { |a| a.name != "src" && a.value.to_s.match?(IMAGE_URL) }
    end

    # Every later step reads href, which may be missing or blank. A
    # template placeholder ("{url}") is no target.
    def restore_link_target(link)
      target = LINK_TARGETS.lazy.map { |name| link[name].to_s.strip }.find { |value| !value.empty? }
      link["href"] = target if target && !target.match?(/[{}]/)
    end

    # A player is kept as an empty element with the file it plays, for the
    # renderer to link to. Muted videos are autoplaying backgrounds. One
    # inside a link is a preview of the page it links to: its file is not
    # content, but a thumbnail it holds for browsers without video stays in
    # its place, inside the link. Fallback text only says the player failed.
    # Only its own children are read: a search of each nested player's
    # subtree would take quadratic time.
    def keep_playable(media)
      src = playable_source(media)
      return media.remove if src.nil? || media.key?("muted")
      return media.replace(thumbnails(media)) unless standalone_player?(media)

      media.children.remove
      media["src"] = src
    end

    def thumbnails(media)
      Nokolexbor::NodeSet.new(media.document, media.element_children.select { |child| %w[img picture].include?(child.name) })
    end

    # Its src, or that of a <source> in it. Blob URLs exist only in the
    # browser that made them.
    def playable_source(media)
      return media["src"].strip if playable?(media["src"])

      source = media.element_children.find { |child| child.name == "source" && playable?(child["src"]) }
      source && source["src"].strip
    end

    def playable?(src)
      src = src.to_s.strip
      !src.empty? && !src.match?(/\A(?:blob|data):/i)
    end

    # Not in a link, and within MAX_DEPTH levels of <body>: a deeper player
    # would become plain text, and walking up from each player of a deep
    # nest to the top would take quadratic time. One whose outer player was
    # emptied first has no way up at all.
    def standalone_player?(media)
      node = media.parent
      MAX_DEPTH.times do
        return false if node.nil? || node.name == "a"
        return true if node == @body

        node = node.parent
      end
      false
    end

    def restore_picture_sources
      @body.css("picture").each do |picture|
        img = picture.at_css("img")
        next if img.nil? || img["src"] || img["srcset"]

        source = picture.css("source").find { |s| s["srcset"] || s["data-srcset"] }
        img["srcset"] = source["srcset"] || source["data-srcset"] if source
      end
    end

    def remove_hidden
      total = Dom.char_count(@body.content)
      @panel_ids = @body.css("[aria-controls]").flat_map { |control| control["aria-controls"].split }.to_set
      @body.css(HIDDEN_CANDIDATES).each do |node|
        next unless hidden?(node)
        # A hidden wrapper around most of the page is an anti-flicker snippet
        # or an open modal in the snapshot, not something readers cannot see.
        next if total > 500 && Dom.char_count(node.content) > total * 0.3 && page_like?(node)

        node.remove
      end
    end

    def page_like?(node)
      titles(node).size == titles(@body).size
    end

    # A site logo marked up as an <h1> is on every page, outside any wrapper.
    def titles(root)
      root.css("h1").reject { |h1| logo?(h1) }
    end

    def logo?(h1)
      return true if Dom.ancestors_named(h1, "nav").any?
      return !h1.at_css("img").nil? if Dom.text(h1).empty?

      home = [*Dom.ancestors_named(h1, "a"), *h1.css("a")].find { |link| home_link?(link["href"].to_s.strip) }
      home && Dom.text(h1).length <= Dom.text(home).length
    end

    def home_link?(href)
      !href.empty? && href.match?(HOME_LINK)
    end

    def hidden?(node)
      return !disclosure?(node) if node.key?("hidden") && node["hidden"] != "until-found"
      return !node["class"].to_s.include?("fallback-image") && !closed_panel?(node) if node["aria-hidden"] == "true"
      return !disclosure?(node) if node["style"].to_s.match?(HIDDEN_STYLE)

      hidden_by_class?(node) && !disclosure?(node)
    end

    def hidden_by_class?(node)
      classes = node["class"].to_s.split
      classes.any? { |c| HIDDEN_CLASSES.include?(c) } && classes.none? { |c| c.match?(RESPONSIVE_SHOW) }
    end

    def disclosure?(node)
      node["role"] == "tabpanel" || Dom.signature(node).match?(Patterns::DISCLOSURE) || accordion_panel?(node)
    end

    def accordion_panel?(node)
      @panel_ids.include?(node["id"]) && (node.key?("aria-labelledby") || node["role"] == "region")
    end

    # Accordions and tabs mark closed panels aria-hidden, but icons and the
    # full text behind "read more" are aria-hidden too, so a panel only counts
    # when a control on the page opens it or a tab labels it.
    def closed_panel?(node)
      disclosure?(node) && (node.key?("aria-labelledby") || @panel_ids.include?(node["id"]))
    end

    def remove_form_controls
      return remove_inputs if @full

      @body.css("form").each { |form| form.remove if utility_form?(form) }
      @body.css("input").each { |input| input.remove unless task_checkbox?(input) }
      @body.css("button").each { |button| disclosure_button?(button) ? button.replace(button.children) : button.remove }
      @body.css("label").each { |label| label.remove if label["for"] || Dom.ancestors_named(label, "form").any? }
      @body.css("form").each { |form| form.remove if leftover_form?(form) }
    end

    # Converting the whole page keeps the text of forms, buttons and labels.
    def remove_inputs
      @body.css("input").each { |input| input.remove unless task_checkbox?(input) }
      @body.css("button").each { |button| button.replace(button.children) }
    end

    # Only a prompt such as "Search:" is left once the controls are gone.
    def leftover_form?(form)
      text = Dom.text(form)
      text.length < 30 && !text.match?(/\d/) && form.at_css("img").nil?
    end

    def task_checkbox?(input)
      input["type"].to_s.casecmp?("checkbox") && input.parent&.name == "li"
    end

    # Search boxes, sign-ups and logins. Forms that wrap real content (ASP.NET
    # pages, product option pickers) are left alone.
    def utility_form?(form)
      return false if Dom.char_count(form.content) >= 300

      form["role"] == "search" ||
        form.css("input").any? { |i| %w[search email password].include?(i["type"].to_s.downcase) } ||
        form["action"].to_s.match?(/search|subscribe|newsletter|login|sign-?in|sign-?up/i) ||
        Dom.signature(form).match?(Patterns::NOISE)
    end

    # Runs last, so the text kept is only what would have been rendered, the
    # content of <noscript> included.
    def flatten_deep_elements
      @body.xpath(".#{'/*' * MAX_DEPTH}[*]").each do |node|
        text = @body.document.create_text_node(flat_text(node))
        node.children.remove
        text_wrappers(node).reverse_each { |name| text = wrap(name, text) }
        node.add_child(text)
      end
    end

    # Text of every descendant, without recursion. Block boundaries and <br>
    # become line breaks, so words stay apart; <pre> keeps them as lines.
    def flat_text(node)
      text = +""
      pending = node.children.to_a.reverse
      until pending.empty?
        current = pending.pop
        if current.is_a?(String)
          text << current
        elsif current.text? || current.cdata?
          text << current.content
        elsif current.name == "br"
          text << "\n"
        elsif current.element?
          boundary = Dom::BLOCK.include?(current.name)
          text << "\n" if boundary
          pending << "\n" if boundary
          pending.concat(current.children.to_a.reverse)
        end
      end
      text
    end

    # A <div> in a <dl> is read for its <dt>s and <dd>s, like the <dl>.
    def text_wrappers(node)
      return TEXT_WRAPPERS[node.name] if TEXT_WRAPPERS.key?(node.name)
      return [] unless node.name == "div"

      parent = node.parent
      parent = parent.parent while parent&.name == "div"
      parent&.name == "dl" ? %w[dd] : []
    end

    def wrap(name, child)
      element = @body.document.create_element(name)
      element.add_child(child)
      element
    end

    # Accordion triggers usually carry the question text of an FAQ.
    def disclosure_button?(button)
      parent = button.parent
      return false unless button.key?("aria-expanded") || button.key?("aria-controls") || (parent && Dom.heading?(parent))

      Dom.text(button).split.size >= 3
    end
  end
end

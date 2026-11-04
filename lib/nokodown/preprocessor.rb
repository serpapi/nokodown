# frozen_string_literal: true

module Nokodown
  # Removes everything that can never be content: scripts, invisible elements,
  # form controls, embeds. Lazy-loaded images are restored first so their
  # placeholders are not mistaken for decoration.
  class Preprocessor
    JUNK = %w[
      script style noscript template link meta base object embed applet param canvas map area svg
      source track audio video dialog select option optgroup datalist textarea output progress meter
      keygen frame frameset portal slot
    ].join(",").freeze

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

    VIDEO_HOSTS = %r{//(?:www\.)?(?:(?:dailymotion|youtube|youtube-nocookie|player\.vimeo|v\.qq|bilibili|live\.bilibili)\.com|(?:archive|upload\.wikimedia)\.org|player\.twitch\.tv|fast\.wistia\.(?:net|com)|play\.vidyard\.com|loom\.com/embed)}i.freeze

    IMAGE_URL = /\.(?:jpe?g|png|webp|gif|avif)(?:[?#]\S*)?\s*\z/i.freeze
    IMAGE_SRCSET = /\.(?:jpe?g|png|webp|gif|avif)(?:\?\S*)?\s+\d/i.freeze
    LAZY_SRC = %w[
      data-src data-lazy-src data-original data-lazy data-url data-hi-res-src data-full-src
      data-large-src data-orig-src data-actualsrc data-echo data-img-src data-image
    ].freeze
    LAZY_SRCSET = %w[data-srcset data-lazy-srcset data-original-set].freeze

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

    def initialize(body)
      @body = body
    end

    def call
      place_streamed_segments
      @body.xpath(".//comment()").each(&:remove)
      unwrap_noscript
      @body.css("img").each { |img| restore_lazy_image(img) }
      restore_picture_sources
      @body.css(JUNK).each(&:remove)
      @body.css("iframe").each { |iframe| iframe.remove unless iframe["src"].to_s.match?(VIDEO_HOSTS) }
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

    def restore_lazy_image(img)
      img.remove_attribute("src") if placeholder_src?(img)
      return if img["src"] && !img["class"].to_s.downcase.include?("lazy")

      copy_first_attribute(img, LAZY_SRC, "src")
      copy_first_attribute(img, LAZY_SRCSET, "srcset")
      restore_from_any_attribute(img) unless img["src"] || img["srcset"]
    end

    def copy_first_attribute(img, names, target)
      value = names.map { |name| img[name].to_s.strip }.find { |v| !v.empty? && !v.start_with?("data:") }
      img[target] = value if value
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

    # Tiny base64 GIF/PNG stand-ins that a lazy loader swaps out.
    def placeholder_src?(img)
      src = img["src"].to_s.strip
      return false unless src.start_with?("data:")
      return false if src.start_with?("data:image/svg+xml") && src.length > 200

      src.length < 300 || img.attribute_nodes.any? { |a| a.name != "src" && a.value.to_s.match?(IMAGE_URL) }
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
      @body.css("form").each { |form| form.remove if utility_form?(form) }
      @body.css("input").each { |input| input.remove unless task_checkbox?(input) }
      @body.css("button").each { |button| disclosure_button?(button) ? button.replace(button.children) : button.remove }
      @body.css("label").each { |label| label.remove if label["for"] || Dom.ancestors_named(label, "form").any? }
      @body.css("form").each { |form| form.remove if leftover_form?(form) }
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

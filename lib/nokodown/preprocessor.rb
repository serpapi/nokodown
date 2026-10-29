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
      print-only visible-print d-print-block show-for-sr w-condition-invisible w-form-done w-form-fail
    ]).freeze

    # Found by Lexbor's selector engine, so the checks below only run on
    # elements that could be hidden.
    HIDDEN_CANDIDATES = (["[hidden]", "[aria-hidden=true]", "[style]"] + HIDDEN_CLASSES.map { |name| ".#{name}" }).join(", ").freeze

    # Utility classes that make a "hidden" element visible again at some breakpoint.
    RESPONSIVE_SHOW = /\A(?:(?:sm|md|lg|xl|2xl):(?:block|flex|grid|inline|inline-block|inline-flex|table|contents)|d-(?:sm|md|lg|xl|xxl)-(?:block|flex|grid|inline|inline-block|inline-flex|table))\z/.freeze

    NARROW_COPY = /\A(?:sm|md|lg|xl|2xl):hidden\z/.freeze

    STREAMED_LINK_SHARE = 0.5

    UTILITY_FORM_TEXT = 300
    # Set on a main region once its text besides headings is measured.
    REGION_TEXT = "data-nokodown-region-text"
    SENDER_INPUTS = ["", "text", "email"].freeze
    QUANTITY = /qty|quantity/i.freeze
    FORM_CONTENT = "h1, main, article, [role=main], video, iframe"
    FORM_PAGE_TEXT = 100

    HIDDEN_STYLE = /(?:\A|;)\s*(?:display\s*:\s*none|visibility\s*:\s*hidden)/i.freeze

    # Injected link spam, honeypot fields and hidden copies of the page are
    # placed far off screen or in a strip one pixel high; collapsed panels
    # have no height. A box clipped to one pixel where it stands is
    # screen-reader text, which can be the only copy of a price. Moved off
    # screen as well, such boxes held only spam, skip links and copies.
    POSITIONED_STYLE = /(?:\A|;)\s*position\s*:\s*(?:absolute|fixed)/i.freeze
    OFFSCREEN_STYLE = /(?:\A|;)\s*(?:left|top)\s*:\s*-(?:\d{4,}(?:\.\d+)?px|999px|\d{3,}(?:\.\d+)?r?em)/i.freeze
    PIXEL_STRIP_STYLE = /(?:\A|;)\s*height\s*:\s*1px/i.freeze
    PIXEL_WIDE_STYLE = /(?:\A|;)\s*width\s*:\s*1px/i.freeze
    OVERFLOW_HIDDEN = /(?:\A|;)\s*overflow\s*:\s*hidden/i.freeze

    LINE_NUMBERS = /(?<![a-z])(?:line-?numbers?(?:-rows)?|linenos?|lineno|gutter|hljs-ln-numbers|ln-num)(?![a-z])/.freeze

    VIDEO_HOSTS = %r{//(?:www\.)?(?:(?:dailymotion|youtube|youtube-nocookie|player\.vimeo|v\.qq|bilibili|live\.bilibili)\.com|(?:archive|upload\.wikimedia)\.org|player\.twitch\.tv|fast\.wistia\.(?:net|com)|play\.vidyard\.com|loom\.com/embed)}i.freeze

    IMAGE_URL = /\.(?:jpe?g|png|webp|gif|avif)(?:[?#]\S*)?\s*\z/i.freeze
    IMAGE_SRCSET = /\.(?:jpe?g|png|webp|gif|avif)(?:\?\S*)?\s+\d/i.freeze
    LAZY_SRC = %w[
      data-src data-lazy-src data-original data-lazy data-url data-hi-res-src data-full-src
      data-large-src data-orig-src data-actualsrc data-echo data-img-src data-image
    ].freeze
    LAZY_SRCSET = %w[data-srcset data-lazy-srcset data-original-set].freeze

    def initialize(body)
      @body = body
    end

    def call
      place_streamed_segments
      @body.xpath(".//comment()").each(&:remove)
      ProtectedEmails.reveal(@body)
      unwrap_noscript
      @body.css("img").each { |img| restore_lazy_image(img) }
      restore_picture_sources
      mark_message_forms
      @body.css(JUNK).each(&:remove)
      LeakedMarkup.clean(@body)
      @body.css("iframe").each { |iframe| iframe.remove unless iframe["src"].to_s.match?(VIDEO_HOSTS) }
      @body.css("pre [class], table[class] td[class]").each { |node| node.remove if node["class"].downcase.match?(LINE_NUMBERS) }
      remove_hidden
      keep_message_marks
      remove_form_controls
      HeadingAnchors.mark(@body)
      Dom.assign_keys(@body)
      mark_wide_copies
    end

    private

    def place_streamed_segments
      @body.css("div[hidden][id^='S:']").each do |segment|
        number = segment["id"].delete_prefix("S:")
        slot = @body.at_css("template[id='B:#{number}'], template[id='P:#{number}']")
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

    def remove_fallback(slot)
      fallback = []
      node = slot.next_sibling
      until node.nil? || (node.comment? && node.content == "/$")
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
      @panel_ids = panel_ids
      @body.css(HIDDEN_CANDIDATES).each do |node|
        next unless hidden?(node)
        # A hidden wrapper around most of the page is an anti-flicker snippet
        # or an open modal in the snapshot, not something readers cannot see.
        next if total > 500 && Dom.char_count(node.content) > total * 0.3 && page_like?(node)

        node.remove
      end
    end

    def panel_ids
      @body.css("[aria-controls]").flat_map { |control| control["aria-controls"].split }.to_set
    end

    def page_like?(node)
      node.css("h1").size == @body.css("h1").size
    end

    # Page builders lay a block out twice, "hidden md:grid" for wide screens
    # beside "md:hidden" for narrow ones. The wide copy is marked so that
    # conditional cleaning, which weighs "hidden" against both, keeps one.
    def mark_wide_copies
      narrow = @body.css("[class*=':hidden']").select { |node| narrow_copy?(node) }
      return if narrow.empty?

      parents = narrow.map { |node| Dom.key(node.parent) }.to_set
      @body.css(".hidden").each { |node| node[Dom::WIDE_COPY] = "" if parents.include?(Dom.key(node.parent)) }
    end

    def narrow_copy?(node)
      node["class"].split.any? { |token| token.match?(NARROW_COPY) }
    end

    def hidden?(node)
      return !disclosure?(node) if node.key?("hidden") && node["hidden"] != "until-found"
      return !node["class"].to_s.include?("fallback-image") && !closed_panel?(node) if node["aria-hidden"] == "true"
      return !disclosure?(node) if node["style"].to_s.match?(HIDDEN_STYLE) || out_of_sight?(node["style"].to_s)

      hidden_by_class?(node) && !disclosure?(node)
    end

    def out_of_sight?(style)
      return true if style.match?(OFFSCREEN_STYLE) && style.match?(POSITIONED_STYLE)

      style.match?(PIXEL_STRIP_STYLE) && style.match?(OVERFLOW_HIDDEN) && !style.match?(PIXEL_WIDE_STYLE)
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

    # A message form that goes stays as an empty mark for MessageForms, which
    # takes the title above it once the content is chosen.
    def remove_form_controls
      @body.css("form").each { |form| drop_form(form) if utility_form?(form) }
      @body.css("input").each { |input| input.remove unless task_checkbox?(input) }
      @body.css("button").each { |button| disclosure_button?(button) ? button.replace(button.children) : button.remove }
      @body.css("label").each { |label| label.remove if label["for"] || Dom.ancestors_named(label, "form").any? }
      @body.css("form").each { |form| drop_form(form) if leftover_form?(form) }
    end

    def drop_form(form)
      form.key?(MessageForms::MARK) ? form.children.each(&:remove) : form.remove
    end

    # Text boxes go with the junk, so the forms that ask for a message in a
    # box readers can see are marked first.
    def mark_message_forms
      @panel_ids = panel_ids
      @body.css("form").each do |form|
        form[MessageForms::MARK] = "" if form.css("textarea").any? { |box| shown?(box) }
      end
    end

    # Hidden itself or by a wrapper inside the form; a hidden form goes whole.
    def shown?(box)
      node = box
      until node.nil? || node.name == "form"
        return false if hidden?(node)

        node = node.parent
      end
      true
    end

    # Comment, review and contact forms ask who writes as well as what.
    def keep_message_marks
      @body.css("form[#{MessageForms::MARK}]").each do |form|
        form.remove_attribute(MessageForms::MARK) unless message_form?(form)
      end
    end

    # A message form holds a few labels and notes; its pictures are a
    # captcha, smileys or rating stars. The form ASP.NET wraps a page in, or
    # one holding the page's title, main region or the address to write to,
    # holds the page. One that asks how many orders something, with a note
    # for the cake or the engraving.
    def message_form?(form)
      return false if form.parent&.name == "body" || form.at_css(FORM_CONTENT)
      return false if Dom.char_count(form.content) >= UTILITY_FORM_TEXT
      return false if form.content.match?(MessageForms::CONTACT_DETAIL)

      inputs = form.css("input")
      return false if inputs.none? { |input| SENDER_INPUTS.include?(input["type"].to_s.downcase) }

      inputs.none? { |input| quantity?(input) } && !page_form?(form)
    end

    def quantity?(input)
      input["type"].to_s.casecmp?("number") || input["name"].to_s.match?(QUANTITY)
    end

    # On an application or sign-up page the form is what the main region
    # holds besides its headings, and what it asks for says what the page is
    # for. A comment form is never that.
    def page_form?(form)
      holder = form
      holder = holder.parent while holder&.element? && !main_region?(holder) && !comment_area?(holder)
      return false unless holder&.element? && main_region?(holder)

      region_text(holder) - (Dom.char_count(form.content) - heading_chars(form)) < FORM_PAGE_TEXT
    end

    # A thread's replies share their region, which is measured once.
    def region_text(holder)
      holder[REGION_TEXT] ||= (Dom.char_count(holder.content) - heading_chars(holder)).to_s
      holder[REGION_TEXT].to_i
    end

    def heading_chars(node)
      node.css(Dom::HEADING_SELECTOR).sum { |heading| Dom.char_count(heading.content) }
    end

    def main_region?(node)
      Boilerplate::CONTENT_ANCESTORS.include?(node.name) || node["role"] == "main"
    end

    def comment_area?(node)
      Dom.signature(node).match?(Patterns::SECONDARY)
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
      return false if Dom.char_count(form.content) >= UTILITY_FORM_TEXT

      form["role"] == "search" ||
        form.css("input").any? { |i| %w[search email password].include?(i["type"].to_s.downcase) } ||
        form["action"].to_s.match?(/search|subscribe|newsletter|login|sign-?in|sign-?up/i) ||
        Dom.signature(form).match?(Patterns::NOISE)
    end

    # Accordion triggers usually carry the question text of an FAQ.
    def disclosure_button?(button)
      parent = button.parent
      return false unless button.key?("aria-expanded") || button.key?("aria-controls") || (parent && Dom.heading?(parent))

      Dom.text(button).split.size >= 3
    end
  end
end

# frozen_string_literal: true

module Nokodown
  # Removes site furniture (navigation, headers, footers, sidebars) and noise
  # widgets (ads, cookie banners, share bars) from the whole page.
  #
  # No rule may remove a content landmark, an ancestor of one, or an element
  # holding most of the page's prose: class names such as "has-sidebar" and
  # ad-targeting attributes routinely sit on the wrappers around the content.
  class Boilerplate
    LANDMARKS = "main, [role=main], [itemprop~=articleBody]"
    CONTENT_ANCESTORS = %w[article main].freeze
    SECTIONING = %w[article aside main nav section].freeze
    PHRASING = Set.new(%w[a abbr b bdi bdo cite code data dfn em i kbd mark q s samp small span strong sub sup time u var]).freeze
    AD_ATTRIBUTES = %w[data-ad-slot data-ad-unit data-adunit data-ad-client data-google-query-id data-ad-format].freeze
    DRAWER = /(?<![a-z])drawer(?![a-z])/.freeze
    TAXONOMY = /(?<![\w-])(?:tag|category|has)-[\w-]+/.freeze
    # What a wrapper has, lacks or allows does not name it: "has-sidebar",
    # "with-navigation", "content-and-menu", "sidebar-enabled--true". The
    # head of a compound names the wrapper, so "menu-and-content" stays a
    # menu. "no-print" names what is left out of print, so it stays too.
    MODIFIER = /
      (?:(?<![\w-])(?:has|with|without|no(?!-?print))|-(?:and|with|without))-[\w-]+|
      (?<![\w-])[\w-]+-(?:enabled|disabled)(?:--[\w-]+)?(?![\w-])
    /x.freeze
    MIN_CARD_RUN = 3
    MIN_LEFT = 200
    CARD_RUN_SHARE = 0.2
    TITLE_HOLDER_SHARE = 0.25
    # A note continues the prose only after a sentence or more of it, not after a line of links.
    NOTE_PROSE = 80
    FOOTNOTE_MARK = /\A[*†‡§]+/.freeze
    # The word goes with its separators: "footer__disclaimer" without it is "footer", not "footer__".
    DISCLAIMER_WORD = /[-_]*#{Patterns::DISCLAIMER.source}[-_]*/.freeze

    def initialize(body)
      @body = body
    end

    def call
      @stats = Stats.new(@body)
      @total = @stats.text_chars(@body)
      @shielded = shielded_keys
      @single_h1 = @body.css("h1").size == 1
      @trails = Breadcrumbs.trails(@body).map { |trail| Dom.key(trail) }.to_set
      @last_h1 = @body.css("h1").map { |h1| Dom.key(h1).to_i }.max.to_i
      # Card grids repeat the same class list hundreds of times.
      @names = Hash.new { |cache, signature| cache[signature] = signature.gsub(MODIFIER, " ") }
      @furniture = Hash.new { |cache, signature| cache[signature] = @names[signature].match?(Patterns::PAGE_FURNITURE) }
      @disclaimer_only = Hash.new { |cache, signature| cache[signature] = disclaimer_only?(signature) }
      @notes = Set.new
      @prose_blocks = Set.new
      @card_classes = card_classes
      @card_bases = @card_classes.map { |classes| base_classes(classes) }
      removals = []
      walk(@body, removals)
      removals.delete(content_guess(removals)) if almost_empty_without?(removals)
      removals.each { |node, kind| kind == :panel ? MemberPanel.reduce(node) : node.remove }
      # The lines panels leave are new elements, and later passes measure by key.
      Dom.assign_keys(@body) if removals.any? { |_, kind| kind == :panel }
    end

    private

    def shielded_keys
      landmarks = @body.css(LANDMARKS).to_a
      articles = @body.css("article")
      landmarks << articles.first if articles.size == 1
      landmarks.flat_map { |node| [node] + node.ancestors.to_a }.map { |node| Dom.key(node) }.compact.to_set
    end

    # Code is never furniture, whatever classes its highlighter gives tokens.
    def walk(node, removals)
      node.element_children.each do |child|
        next if Dom::CODE.include?(child.name)

        kind = removal(child)
        kind ? removals << [child, kind] : walk(child, removals)
      end
    end

    def almost_empty_without?(removals)
      @stats.chars(@body) - removals.sum { |node, _| @stats.chars(node) } < MIN_LEFT
    end

    def content_guess(removals)
      guess = removals.select { |_, kind| kind == :guess }.max_by { |node, _| @stats.chars(node) }
      return unless guess && @stats.chars(guess.first) >= MIN_LEFT

      signature = Dom.signature(guess.first)
      guess unless signature.match?(Patterns::PLACE) || signature.match?(Patterns::OVERLAY)
    end

    # Semantic chrome (nav, a page-level footer) goes even when it outweighs
    # the content, as legal footnotes often do; class-name guesses do not.
    def removal(node)
      return if @shielded.include?(Dom.key(node))
      # Side notes inside an article are content whatever their class says.
      return if node.name == "aside" && !aside_noise?(node)
      return :chrome if (chrome_element?(node) || chrome_role?(node)) && !title_holder?(node)
      return if dominant?(node) && !header_above_title?(node)
      return :guess if trail?(node)
      return unless advertising?(node) || share_intent?(node) || chrome_label?(node) || class_noise?(node)
      return if inside_sentence?(node)

      MemberPanel.panel?(node) ? :panel : :guess
    end

    # Themes render the post in a <footer> or in a complementary reading
    # pane. One that holds the page's only h1 and a fair share of its text is
    # the content.
    def title_holder?(node)
      return false unless node.name == "footer" || node.name == "aside" || node["role"] == "complementary"

      @single_h1 && !node.at_css("h1").nil? && @stats.text_chars(node) >= @total * TITLE_HOLDER_SHARE
    end

    # A trail stands apart from the text around it; one that words lead into
    # or out of is part of a sentence ("Open Home › Account and pick...").
    def trail?(node)
      return false unless @trails.include?(Dom.key(node))

      [node.previous_sibling, node.next_sibling].none? { |sibling| sibling&.text? && !Dom.squish(sibling.content).empty? }
    end

    # A link or span in the middle of running text is part of that text,
    # whatever its class says ("recommendation-inline-link", "tooltip-term").
    def inside_sentence?(node)
      return false unless PHRASING.include?(node.name) && node.parent

      @stats.chars(node.parent) - @stats.chars(node) >= 20
    end

    def chrome_element?(node)
      case node.name
      when "nav" then true
      when "footer" then !inside_sectioning?(node)
      when "header" then site_header?(node)
      when "aside" then aside_noise?(node)
      else false
      end
    end

    def chrome_role?(node)
      role = node["role"]
      return false unless role && Patterns::CHROME_ROLES.include?(role)

      case role
      when "complementary" then aside_noise?(node)
      when "banner" then site_header?(node)
      when "alert", "status" then Dom.char_count(node.content) < 300
      when "tablist" then tab_strip?(node)
      else true
      end
    end

    # Sites also put role=tablist on the wrapper around the tabs and their
    # panels, or on an FAQ accordion; only a strip of short labels or links
    # is chrome.
    def tab_strip?(node)
      return false if node.at_css("[role=tabpanel]")

      @stats.text_chars(node) < 200 || @stats.link_density(node) > 0.5
    end

    def advertising?(node)
      return true if node.name == "ins" && node["class"].to_s.include?("adsbygoogle")
      return true if node["id"].to_s.start_with?("div-gpt-ad", "google_ads")

      AD_ATTRIBUTES.any? { |name| node.key?(name) }
    end

    # A link that asks a network to share the page is a share button in any
    # language, whatever its label ("シェア", "Partager sur LinkedIn").
    def share_intent?(node)
      node.name == "a" && node["href"].to_s.strip.match?(Patterns::SHARE_INTENT)
    end

    def chrome_label?(node)
      return true if node["itemtype"].to_s.match?(Patterns::CHROME_ITEMTYPES)

      node["aria-label"].to_s.match?(Patterns::ARIA_LABEL) && !%w[main article].include?(node.name)
    end

    def class_noise?(node)
      return false if !@prose_blocks.empty? && prose_part?(node)

      furniture_class?(node) && !content_note?(node) && (@card_bases.empty? || !card?(node))
    end

    # Fine print about the site is furniture, but a note on the content right
    # before it belongs to that content: a paragraph continuing the prose, or
    # the footnote to a mark in it ("40-46 states*"). Widgets nest the note's
    # text in an element named like the note.
    def content_note?(node)
      return false unless @disclaimer_only[Dom.signature(node)]

      note = @notes.include?(Dom.key(node.parent)) || annotates_previous?(node)
      @notes << Dom.key(node) if note
      note
    end

    def annotates_previous?(node)
      previous = node.previous_element
      return false unless previous

      prose_note?(node, previous) || footnote_to?(node, previous)
    end

    def prose_note?(node, previous)
      return false unless node.name == "p" && previous.name == "p"

      @stats.text_chars(previous) >= NOTE_PROSE && !@furniture[Dom.signature(previous)]
    end

    def footnote_to?(node, previous)
      marks = [node, *node.css("p, li")].map { |line| Dom.text(line)[FOOTNOTE_MARK] }.compact.uniq
      marks.any? { |mark| previous.content.match?(/[[:alnum:]]#{Regexp.escape(mark)}/) }
    end

    # Only a signature that is furniture for its disclaimer name alone can be
    # a note; "ad-disclaimer" or "footer__disclaimer" stays furniture.
    def disclaimer_only?(signature)
      signature.match?(Patterns::DISCLAIMER) && !signature.gsub(DISCLAIMER_WORD, " ").match?(Patterns::PAGE_FURNITURE)
    end

    def card?(node)
      classes = base_classes(node["class"])
      @card_bases.any? { |base| (base - classes).empty? } && card_candidate?(node)
    end

    def base_classes(classes)
      classes.to_s.split.reject { |token| token.include?("--") }
    end

    def prose_part?(node)
      node["class"].to_s.split.any? { |token| @prose_blocks.any? { |block| token.start_with?("#{block}_", "#{block}-") } }
    end

    def furniture_class?(node)
      signature = Dom.signature(node)
      return false if signature.empty?

      chrome = @furniture[signature]
      return site_header?(node) if !chrome && @names[signature].match?(Patterns::HEADER)
      return @stats.link_density(node) > 0.5 if !chrome && @names[signature].match?(Patterns::MENU)
      return false unless chrome
      return false if prose_section?(node, signature)
      return true if signature.gsub(TAXONOMY, " ").match?(Patterns::NOISE)

      !(signature.match?(Patterns::POSITIVE) && @stats.text_chars(node) >= 200)
    end

    # Sections named after the TOC entry or skip link that points to them
    # ("toc-para", "skip-item") and accordions named "drawer" like slide-out
    # panels are content when they hold prose. Furniture named for its place
    # on the page or for an overlay, ad or share bar is not.
    def prose_section?(node, signature)
      return false if @stats.text_chars(node) < 400 || @stats.link_density(node) >= 0.2
      return false if signature.match?(Patterns::PLACE) || signature.gsub(DRAWER, " ").match?(Patterns::NOISE)
      return false if node.css("p").size < 2

      @prose_blocks.merge(node["class"].to_s.split.select { |token| token.downcase.match?(Patterns::PAGE_FURNITURE) })
      true
    end

    # A hub page often splits its content into modules named after their role
    # elsewhere ("recirc-list", "hide-read-more-ad"). None holds enough of the
    # page to be dominant, so a run of them is judged as a whole. Card text
    # is link text, so all characters count.
    def card_classes
      min_chars = @stats.chars(@body) * CARD_RUN_SHARE
      runs = @body.css("[class]").group_by { |node| node["class"] }
      runs.each_with_object(Set.new) do |(classes, nodes), cards|
        cards << classes if card_run?(classes, nodes, min_chars)
      end
    end

    def card_run?(classes, nodes, min_chars)
      # Most class lists fail on size or name alone, before the slower checks below.
      return false if nodes.size < MIN_CARD_RUN || !(furniture_name?(classes) || nodes.any? { |node| node.key?("id") })
      return false if nodes.sum { |node| @stats.chars(node) } < min_chars

      cards = nodes.select { |node| card_candidate?(node) }
      # Wrappers repeating their child's class would count its text twice.
      cards.reject! { |node| node.ancestors.any? { |ancestor| ancestor.element? && ancestor["class"] == classes } }
      cards.size >= MIN_CARD_RUN && cards.sum { |node| @stats.chars(node) } >= min_chars
    end

    def furniture_name?(classes)
      signature = Dom.signature_of("#{classes} ")
      @furniture[signature] || @names[signature].match?(Patterns::HEADER) || @names[signature].match?(Patterns::MENU)
    end

    # Menus repeat their items too, so a run named after a place is never
    # content, and neither is a run of cookie categories or dialogs.
    def card_candidate?(node)
      return false if @shielded.include?(Dom.key(node)) || !furniture_class?(node)
      return false if Dom.signature(node).match?(Patterns::PLACE) || Dom.signature(node).match?(Patterns::OVERLAY)

      !chrome_element?(node) && !chrome_role?(node)
    end

    # Per the HTML spec a header inside sectioning content belongs to that
    # section; outside, one holding the page title (h1, few links, no
    # navigation) is still content.
    def site_header?(node)
      return false if inside_sectioning?(node) || (dominant?(node) && !header_above_title?(node))

      title_block = node.at_css("h1") && @stats.link_density(node) < 0.5 && !node.at_css("nav, [role=navigation], [role=search]")
      !title_block
    end

    # A mega menu or a banner of notices can outweigh the content, but the
    # site header holding it still sits above the page's title. Prose is not
    # furniture: Drupal views wrap their whole content in a header, and a
    # banner below may hold the page's only h1.
    def header_above_title?(node)
      return false unless node.name == "header" || Dom.signature(node).match?(Patterns::HEADER)
      return false if node.at_css("h1") || !furniture_shaped?(node)

      Dom.key(last_descendant(node)).to_i < @last_h1
    end

    def furniture_shaped?(node)
      @stats.link_density(node) > 0.5 || node.css("p").none? { |paragraph| @stats.text_chars(paragraph) >= NOTE_PROSE }
    end

    def last_descendant(node)
      node = node.last_element_child while node.last_element_child
      node
    end

    def aside_noise?(node)
      !(inside_content?(node) && @stats.link_density(node) < 0.5)
    end

    def inside_sectioning?(node)
      node.ancestors.any? { |ancestor| ancestor.element? && (SECTIONING.include?(ancestor.name) || ancestor["role"] == "main") }
    end

    def inside_content?(node)
      node.ancestors.any? do |ancestor|
        ancestor.element? && (CONTENT_ANCESTORS.include?(ancestor.name) || ancestor["role"] == "main" ||
          ancestor["itemprop"].to_s.include?("articleBody"))
      end
    end

    def dominant?(node)
      text = @stats.text_chars(node)
      text >= 200 && text >= @total * 0.5
    end
  end
end

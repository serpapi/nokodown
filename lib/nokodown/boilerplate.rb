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
    MIN_CARD_RUN = 3
    CARD_RUN_SHARE = 0.2

    def initialize(body)
      @body = body
    end

    def call
      @stats = Stats.new(@body)
      @total = @stats.text_chars(@body)
      @shielded = shielded_keys
      # Card grids repeat the same class list hundreds of times.
      @furniture = Hash.new { |cache, signature| cache[signature] = signature.match?(Patterns::PAGE_FURNITURE) }
      @card_classes = card_classes
      walk(@body)
    end

    private

    def shielded_keys
      landmarks = @body.css(LANDMARKS).to_a
      articles = @body.css("article")
      landmarks << articles.first if articles.size == 1
      landmarks.flat_map { |node| [node] + node.ancestors.to_a }.map { |node| Dom.key(node) }.compact.to_set
    end

    def walk(node)
      node.element_children.each do |child|
        if remove?(child)
          child.remove
        else
          walk(child)
        end
      end
    end

    # Semantic chrome (nav, a page-level footer) goes even when it outweighs
    # the content, as legal footnotes often do; class-name guesses do not.
    def remove?(node)
      return false if @shielded.include?(Dom.key(node))
      # Side notes inside an article are content whatever their class says.
      return false if node.name == "aside" && !aside_noise?(node)
      return true if chrome_element?(node) || chrome_role?(node)
      return false if dominant?(node)
      return false unless advertising?(node) || chrome_label?(node) || class_noise?(node)

      !inside_sentence?(node)
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
      else true
      end
    end

    def advertising?(node)
      return true if node.name == "ins" && node["class"].to_s.include?("adsbygoogle")
      return true if node["id"].to_s.start_with?("div-gpt-ad", "google_ads")

      AD_ATTRIBUTES.any? { |name| node.key?(name) }
    end

    def chrome_label?(node)
      return true if node["itemtype"].to_s.match?(Patterns::CHROME_ITEMTYPES)

      node["aria-label"].to_s.match?(Patterns::ARIA_LABEL) && !%w[main article].include?(node.name)
    end

    def class_noise?(node)
      furniture_class?(node) && !@card_classes.include?(node["class"])
    end

    def furniture_class?(node)
      signature = Dom.signature(node)
      return false if signature.empty?

      chrome = @furniture[signature]
      return site_header?(node) if !chrome && signature.match?(Patterns::HEADER)
      return @stats.link_density(node) > 0.5 if !chrome && signature.match?(Patterns::MENU)
      return false unless chrome
      return false if prose_section?(node, signature)

      !(signature.match?(Patterns::POSITIVE) && @stats.text_chars(node) >= 200)
    end

    # Sections named after the TOC entry or skip link that points to them
    # ("toc-para", "skip-item") and accordions named "drawer" like slide-out
    # panels are content when they hold prose. Furniture named for its place
    # on the page or for an overlay, ad or share bar is not.
    def prose_section?(node, signature)
      return false if @stats.text_chars(node) < 400 || @stats.link_density(node) >= 0.2
      return false if signature.match?(Patterns::PLACE) || signature.gsub(DRAWER, " ").match?(Patterns::NOISE)

      node.css("p").size >= 2
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
      # Most class lists fail on size alone, before the slower checks below.
      return false if nodes.size < MIN_CARD_RUN || nodes.sum { |node| @stats.chars(node) } < min_chars

      cards = nodes.select { |node| card_candidate?(node) }
      # Wrappers repeating their child's class would count its text twice.
      cards.reject! { |node| node.ancestors.any? { |ancestor| ancestor.element? && ancestor["class"] == classes } }
      cards.size >= MIN_CARD_RUN && cards.sum { |node| @stats.chars(node) } >= min_chars
    end

    # Menus repeat their items too, so a run named after a place is never content.
    def card_candidate?(node)
      return false if @shielded.include?(Dom.key(node)) || !furniture_class?(node)

      !Dom.signature(node).match?(Patterns::PLACE) && !chrome_element?(node) && !chrome_role?(node)
    end

    # Per the HTML spec a header inside sectioning content belongs to that
    # section; outside, one holding the page title (h1, few links, no
    # navigation) is still content.
    def site_header?(node)
      return false if inside_sectioning?(node) || dominant?(node)

      title_block = node.at_css("h1") && @stats.link_density(node) < 0.5 && !node.at_css("nav, [role=navigation], [role=search]")
      !title_block
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

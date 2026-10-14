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

    def initialize(body)
      @body = body
    end

    def call
      @stats = Stats.new(@body)
      @total = @stats.text_chars(@body)
      @shielded = shielded_keys
      # Card grids repeat the same class list hundreds of times.
      @furniture = Hash.new { |cache, signature| cache[signature] = signature.match?(Patterns::PAGE_FURNITURE) }
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

    def chrome_label?(node)
      return true if node["itemtype"].to_s.match?(Patterns::CHROME_ITEMTYPES)

      node["aria-label"].to_s.match?(Patterns::ARIA_LABEL) && !%w[main article].include?(node.name)
    end

    def class_noise?(node)
      signature = Dom.signature(node)
      return false if signature.empty?

      chrome = @furniture[signature]
      return site_header?(node) if !chrome && signature.match?(Patterns::HEADER)
      return @stats.link_density(node) > 0.5 if !chrome && signature.match?(Patterns::MENU)
      return false unless chrome

      !(signature.match?(Patterns::POSITIVE) && @stats.text_chars(node) >= 200)
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

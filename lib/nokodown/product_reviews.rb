# frozen_string_literal: true

module Nokodown
  # Removes customer reviews, ratings and Q&A widgets from product pages.
  # Shoppers' prose easily outweighs a product description, so it would win
  # the content scoring or, in page mode, bury the description. On other
  # pages a reviews section is usually the content itself (a review article,
  # a service's testimonials), so only product pages are cleaned.
  class ProductReviews
    # Shops that declare no product type in JSON-LD or Open Graph. <head> and
    # form controls are gone once the body is cleaned, so this is checked on
    # the raw document.
    PRODUCT_MARKUP = "[itemtype*='schema.org/Product'], meta[property='product:price:amount'], #add-to-cart-button, form[action*='/cart/add']"

    # The product's title and description stay even when a wrapper around
    # them is named after its reviews.
    PROTECTED = "h1, [itemprop~=description]"

    # Testimonials and a book's editorial reviews are the seller's own words.
    SELLER_CONTENT = /testimonial|editorial/.freeze

    ITEMPROP = /\Areviews?\z/i.freeze
    ARIA_LABEL = /\A(?:customer\s)?reviews\z/i.freeze

    # With less text than this left, the reviews are what the page is about.
    MIN_REMAINING_CHARS = 200

    def self.product_page?(doc, page_type)
      page_type == :product || !doc.at_css(PRODUCT_MARKUP).nil?
    end

    def initialize(body)
      @body = body
    end

    def call
      @protected = protected_keys
      # Card grids repeat the same class list hundreds of times.
      @review_names = Hash.new { |cache, signature| cache[signature] = signature.match?(Patterns::REVIEWS) }
      widgets = outermost_widgets(@body)
      return if widgets.empty?

      remaining = Dom.char_count(@body.content) - widgets.sum { |node| Dom.char_count(node.content) }
      widgets.each(&:remove) if remaining >= MIN_REMAINING_CHARS
    end

    private

    # A review's own description (schema.org Review) must not shield the
    # list it sits in.
    def protected_keys
      kept = @body.css(PROTECTED).reject { |node| inside_review_item?(node) }
      kept.flat_map { |node| [node] + node.ancestors.to_a }.map { |node| Dom.key(node) }.compact.to_set
    end

    def inside_review_item?(node)
      node.ancestors.any? { |ancestor| ancestor.element? && ancestor["itemprop"].to_s.match?(ITEMPROP) }
    end

    def outermost_widgets(node, found = [])
      node.element_children.each do |child|
        signature = Dom.signature(child)
        next if signature.match?(SELLER_CONTENT)

        if widget?(child, signature)
          found << child
        else
          outermost_widgets(child, found)
        end
      end
      found
    end

    def widget?(node, signature)
      return false if kept?(node, signature)

      @review_names[signature] || node["itemprop"].to_s.match?(ITEMPROP) || node["aria-label"].to_s.strip.match?(ARIA_LABEL)
    end

    # A rating badge in a line of text ("4.7 stars, 212 reviews") sums the
    # reviews up like a price does. A section named after the description too
    # holds the seller's words, such as critics' quotes on a game page.
    def kept?(node, signature)
      @protected.include?(Dom.key(node)) || Boilerplate::PHRASING.include?(node.name) || signature.include?("description")
    end
  end
end

# frozen_string_literal: true

module Nokodown
  module Markdown
    # Finds images that cost tokens without telling the reader anything: card
    # thumbnails beside a text link to the same page, and images the page
    # marks as decorative. They are still rendered, and Cleanup removes them
    # last, so a heading whose section held only an image keeps its place.
    class RedundantImages
      MONTHS = "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|" \
               "aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"
      # A squashed label that is only a date: "Oct 1, 2026", "1 October".
      DATE = /\A(?:\d+(?:#{MONTHS})\d*|(?:#{MONTHS})\d+)\z/.freeze
      LABEL_SHARE = 0.3

      # Where a link destination points, ignoring the fragment and a trailing
      # slash. ImageCleanup reads the links left in the Markdown this way.
      def self.page(destination)
        destination.sub(/#.*\z/m, "").chomp("/")
      end

      def initialize(nodes, mode, urls)
        @nodes = nodes
        @mode = mode
        @urls = urls
        @text_free = {}
      end

      # Dom keys of the images to drop. A thumbnail maps to the page whose
      # text link names it, a decorative image to nil.
      def call
        links = elements("a").map { |anchor| [anchor, target(anchor)] }.select { |_, page| page }
        labels = link_labels(links)
        redundant = {}
        links.each do |anchor, page|
          thumbnails(anchor, labels[page]).each { |img| redundant[Dom.key(img)] = page }
        end
        elements("img").each { |img| redundant[Dom.key(img)] = nil if decorative?(img) }
        redundant.reject { |key, _| key.nil? }
      end

      private

      def elements(name)
        @nodes.flat_map { |node| (node.name == name ? [node] : []) + node.css(name).to_a }
      end

      # Link texts by page, squashed for comparison with alt text. "Read
      # more" is not written to the Markdown, and "3 comments" names nothing.
      def link_labels(links)
        links.each_with_object({}) do |(anchor, page), labels|
          text = Dom.text(anchor)
          next if text.match?(Patterns::LINK_NOISE_TEXT) || text.match?(Patterns::BOILERPLATE_TEXT)

          label = squash(text)
          (labels[page] ||= []) << label unless label.empty?
        end
      end

      # A link with its own text, or another link to the same page with text,
      # names the destination already. A link to an image file is a zoom, not
      # a card.
      def thumbnails(anchor, labels)
        return [] if labels.nil? || image_link?(anchor)
        return [] if @mode != :page && Dom.ancestors_named(anchor, "figure").any?

        anchor.css("img").select { |img| adds_nothing?(Dom.squish(img["alt"].to_s), labels) }
      end

      # An image without alt text adds nothing to any label. One with an alt
      # needs a label in words, since a price or a date does not say what the
      # page is; page mode then drops it, article mode only if the alt
      # repeats the label.
      def adds_nothing?(alt, labels)
        return true if alt.empty?

        names = labels.select { |label| label.match?(/\p{L}/) && !label.match?(DATE) }
        !names.empty? && (@mode == :page || repeats?(alt, names))
      end

      # An alt of a word or two ("Photo", "Boot") adds nothing either.
      def repeats?(alt, names)
        return true if alt.split.size <= 2

        alt = squash(alt)
        names.any? { |name| name.include?(alt) || (alt.include?(name) && name.length >= alt.length * LABEL_SHARE) }
      end

      # The page a link opens, written as the Markdown link would be.
      def target(anchor)
        url = Inline.link_url(anchor["href"].to_s, @urls)
        RedundantImages.page(Text.destination(url)) if url
      end

      # alt="" and role="presentation" are how HTML marks an image as
      # decorative, but many sites write alt="" on every image. Articles
      # carry their photos in any wrapper, so there only the role counts; on
      # other pages, where an image sits can still make it content. A
      # missing alt says nothing.
      def decorative?(img)
        presentation = %w[presentation none].include?(img["role"].to_s.strip.downcase)
        return false unless presentation || (@mode == :page && img.key?("alt") && Dom.squish(img["alt"]).empty?)

        !Image.content_sized?(img) && !placed_as_content?(img)
      end

      # In a figure, linked to its full-size file, or in a paragraph or table
      # cell without text (a tick in a comparison table).
      def placed_as_content?(img)
        ancestors = Dom.ancestors_named(img, "figure", "a", "p", "td", "th")
        return true if ancestors.any? { |node| node.name == "figure" || image_link?(node) }

        holder = ancestors.find { |node| node.name != "a" }
        !holder.nil? && text_free?(holder)
      end

      # Memoized: on a table layout one cell holds the whole page and all of
      # its images.
      def text_free?(node)
        key = Dom.key(node)
        return @text_free[key] if key && @text_free.key?(key)

        free = Dom.text(node).empty?
        @text_free[key] = free if key
        free
      end

      def image_link?(node)
        node.name == "a" && node["href"].to_s.match?(Preprocessor::IMAGE_URL)
      end

      def squash(text)
        text.downcase.gsub(/[^\p{L}\p{N}]+/, "")
      end
    end
  end
end

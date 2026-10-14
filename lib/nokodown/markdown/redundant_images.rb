# frozen_string_literal: true

module Nokodown
  module Markdown
    # Finds images that cost tokens without telling the reader anything: card
    # thumbnails beside a text link to the same page, and images the page
    # marks as decorative. They are still rendered, and Cleanup removes them
    # last, so a heading whose section held only an image keeps its place.
    class RedundantImages
      def initialize(nodes, mode, urls)
        @nodes = nodes
        @mode = mode
        @urls = urls
      end

      # Dom keys of the images to drop.
      def call
        anchors = elements("a")
        labels = link_labels(anchors)
        images = anchors.flat_map { |anchor| thumbnails(anchor, labels) }
        images.concat(elements("img").select { |img| decorative?(img) })
        Set.new(images.filter_map { |img| Dom.key(img) })
      end

      private

      def elements(name)
        @nodes.flat_map { |node| (node.name == name ? [node] : []) + node.css(name).to_a }
      end

      # Link texts by target, squashed for comparison with alt text.
      def link_labels(anchors)
        anchors.each_with_object({}) do |anchor, labels|
          target = target(anchor)
          label = squash(Dom.text(anchor))
          (labels[target] ||= []) << label if target && !label.empty?
        end
      end

      # A link with its own text, or another link to the same page with text,
      # names the destination already. Page mode drops every image in such a
      # link; article mode only those whose alt adds nothing to the label. A
      # link to an image file is a zoom, not a card.
      def thumbnails(anchor, labels)
        names = labels[target(anchor)]
        return [] if names.nil? || image_link?(anchor)

        anchor.css("img").select { |img| @mode == :page || repeats?(Dom.squish(img["alt"].to_s), names) }
      end

      # An alt of a word or two ("Photo", "Boot") adds nothing either.
      def repeats?(alt, names)
        return true if alt.split.size <= 2

        alt = squash(alt)
        names.any? { |name| name.include?(alt) || alt.include?(name) }
      end

      # Where a link points, ignoring the fragment and a trailing slash.
      def target(anchor)
        href = anchor["href"].to_s.strip
        return if href.empty? || href.start_with?("#") || href.match?(Inline::UNSAFE_SCHEME)

        @urls.resolve(href)&.sub(/#.*\z/m, "")&.chomp("/")
      end

      # alt="" and role="presentation" are how HTML marks an image as
      # decorative, but many sites write alt="" on every image, so where an
      # image sits can still make it content. A missing alt says nothing.
      def decorative?(img)
        return true if %w[presentation none].include?(img["role"].to_s.strip.downcase)
        return false unless img.key?("alt") && Dom.squish(img["alt"]).empty?

        !placed_as_content?(img)
      end

      # In a figure, linked to its full-size file, or in a paragraph or table
      # cell without text (a tick in a comparison table).
      def placed_as_content?(img)
        ancestors = Dom.ancestors_named(img, "figure", "a", "p", "td", "th")
        return true if ancestors.any? { |node| node.name == "figure" || image_link?(node) }

        holder = ancestors.find { |node| node.name != "a" }
        !holder.nil? && Dom.text(holder).empty?
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

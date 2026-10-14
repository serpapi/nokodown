# frozen_string_literal: true

module Nokodown
  module Markdown
    module Image
      TRACKING = %r{(?:\A|/)(?:pixel|spacer|blank|transparent|clear|tracking|beacon|1x1|[\w-]*placeholder)\.(?:gif|png|svg|jpe?g|webp)(?:\?|\z)|/(?:pixel|beacon)(?:/|\?)}i.freeze
      # README status badges: build, version and coverage shields.
      BADGE = %r{//(?:img\.shields\.io|badge\.fury\.io|badgen\.net)/|badge\.svg(?:[?#]|\z)|/badges?/[^?#]*\.svg}i.freeze
      # Emoji, including skin-tone modifiers, variation selectors and joiners.
      EMOJI = /\A[\p{So}\p{Sk}\p{Mn}\p{Cf}]+\z/.freeze

      module_function

      def source(node, urls)
        src = node["src"].to_s.strip
        src = largest_srcset(node["srcset"].to_s) if src.empty? || src.start_with?("data:")
        return if src.nil? || src.empty? || src.start_with?("data:")

        urls.resolve(src)
      end

      def largest_srcset(srcset)
        candidates = srcset.split(/,\s+/).map do |candidate|
          url, descriptor = candidate.strip.split(/\s+/, 2)
          [url, descriptor.to_f]
        end
        candidates.reject { |url, _| url.nil? || url.empty? }.max_by { |_, size| size }&.first
      end

      # Icons, spacers, tracking pixels, placeholders and badges.
      def decorative?(node, src, alt)
        return true if alt.empty? && src.match?(/\.svg(?:[?#]|\z)/i)

        width = pixels(node["width"])
        height = pixels(node["height"])
        return true if (width && width <= 2) || (height && height <= 2)
        return true if width && height && width <= 32 && height <= 32

        src.match?(TRACKING) || src.match?(BADGE)
      end

      def pixels(value)
        value.to_s.strip.match?(/\A\d+(?:px)?\z/) ? value.to_i : nil
      end

      # WordPress and Twitter render emoji as images; the alt is the emoji.
      def emoji?(node, alt)
        node["class"].to_s.match?(/emoji|wp-smiley/) || (alt.length.between?(1, 8) && alt.match?(EMOJI))
      end

      # Wikipedia's math fallback images carry the TeX source as alt text.
      def tex(alt)
        tex = alt.sub(/\A\{\\displaystyle\s*(.*)\}\z/m, '\1').strip
        tex.empty? ? "" : "$#{tex}$"
      end

      def video_page(src)
        id = src[%r{youtube(?:-nocookie)?\.com/embed/([\w-]{6,})}, 1]
        id ? "https://www.youtube.com/watch?v=#{id}" : src
      end
    end
  end
end

# frozen_string_literal: true

module Nokodown
  module Markdown
    module Image
      TRACKING = %r{(?:\A|/)(?:pixel|spacer|blank|transparent|clear|tracking|beacon|1x1|[\w-]*placeholder)\.(?:gif|png|svg|jpe?g|webp)(?:\?|\z)|/(?:pixel|beacon)(?:/|\?)}i.freeze
      # README status badges: build, version and coverage shields.
      BADGE = %r{//(?:img\.shields\.io|badge\.fury\.io|badgen\.net)/|badge\.svg(?:[?#]|\z)|/badges?/[^?#]*\.svg}i.freeze
      # Emoji, including skin-tone modifiers, variation selectors and joiners.
      EMOJI = /\A[\p{So}\p{Sk}\p{Mn}\p{Cf}]+\z/.freeze
      # Alt text that names nothing: a file name, a camera's numbering, a hash,
      # or a word for "image" in the major web languages.
      FILE_NAME = /\A\S+\.(?:jpe?g|png|gif|webp|svg|avif|bmp|tiff?|heic|ico)\z/i.freeze
      CAMERA_NAME = /\A(?:img|dsc[nf]?|dcim|pxl|mvimg|screenshot|scan|photo|image)[\s_-]?\d{3,}|\A[0-9a-f-]{12,}\z/i.freeze
      GENERIC_ALT = /
        \A(?:image|img|photo|picture|pic|thumbnail|thumb|banner|untitled|default|featured\simage|no\simage|
        imagen|imagem|foto|fotografía|fotografia|bild|immagine|afbeelding|изображение|фото|картинка|zdjęcie|obraz|
        resim|görsel|fotoğraf|画像|写真|图片|图像|圖片|描述|이미지|사진|صورة|hình\sảnh|ảnh|gambar)[\s\d#_-]*\z
      /xi.freeze
      # Words of a file name that stands in for an image still loading or
      # missing: "img_load.gif", "no-image.png", "placeholder100.png".
      PLACEHOLDER_WORD = /\A(?:placeholder|noimage|loading|load|lazyload)\d*\z/.freeze
      # Icons, logos and avatars, by file name words, folder, class or alt.
      ICON_WORD = /
        \A(?:logo|icon|ico|ic|favicon|sprite|arrow|chevron|caret|bullet|btn|badge|avatar|gravatar|separator|
        divider|rss|informer|counter)s?\d*\z
      /x.freeze
      ICON_FOLDER = %r{/(?:icons?|logos?|emoji|emojis|flags|avatars?|smilies)/}i.freeze
      ICON_CLASS = /logo|icon|avatar/i.freeze
      ICON_ALT = /
        \b(?:logo|logotipo|logotype|icon|icono|ícone|icône|ikona|иконка|loading|cargando|chargement|carregando)\b
      /xi.freeze
      CONTENT_SIZE = 300

      module_function

      def source(node, urls)
        src = node["src"].to_s.strip
        src = largest_srcset(node["srcset"].to_s) if src.empty? || src.start_with?("data:")
        return if src.nil? || src.empty? || src.start_with?("data:")

        urls.resolve_image(src)
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
        return true if placeholder?(src)
        return true if alt.empty? && src.match?(/\.svg(?:[?#]|\z)/i)

        width = pixels(node["width"])
        height = pixels(node["height"])
        return true if (width && width <= 2) || (height && height <= 2)
        return true if width && height && width <= 32 && height <= 32

        src.match?(TRACKING) || src.match?(BADGE)
      end

      def placeholder?(src)
        words = file_words(src)
        words.any? { |word| word.match?(PLACEHOLDER_WORD) } || words.join.include?("noimage")
      end

      # In the main content an image stays only when its alt text says what
      # it shows, and it is not an icon or a logo; a tick alone in a table
      # cell keeps its place.
      def content?(node, src, alt)
        return true if text_free_cell?(node)

        names?(alt) && !icon?(node, src, alt)
      end

      def names?(alt)
        alt.match?(/\p{L}/) && !alt.match?(FILE_NAME) && !alt.match?(CAMERA_NAME) && !alt.match?(GENERIC_ALT)
      end

      def icon?(node, src, alt)
        return false if [node["width"], node["height"]].any? { |value| pixels(value).to_i >= CONTENT_SIZE }

        file_words(src).any? { |word| word.match?(ICON_WORD) } || src.sub(/[?#].*/m, "").match?(ICON_FOLDER) ||
          "#{node['class']} #{node['id']}".match?(ICON_CLASS) || alt.match?(ICON_ALT) || src.include?("gravatar.com/")
      end

      # "QDLogoBlue.gif" reads as qd, logo, blue.
      def file_words(src)
        name = File.basename(src.sub(/[?#].*/m, ""), ".*")
        name.gsub(/([a-z])([A-Z])|([A-Z])([A-Z][a-z])/, '\\1\\3 \\2\\4').downcase.split(/[^a-z0-9]+/)
      end

      def text_free_cell?(node)
        cell = Dom.ancestors_named(node, "td", "th").first
        !cell.nil? && Dom.text(cell).empty?
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

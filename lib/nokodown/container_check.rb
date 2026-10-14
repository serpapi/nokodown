# frozen_string_literal: true

module Nokodown
  # Readability's conditional cleaning for one container: what it holds (link
  # density, images per paragraph, inputs, embeds) decides whether it is prose
  # or page furniture.
  class ContainerCheck
    HEADINGS = "h1, h2, h3, h4, h5, h6"
    TEXTISH = "span, li, td, blockquote, dl, div, img, ol, p, pre, table, ul"
    AD_WORDS = /\A(?:ad(?:vertising|vertisement)?|pub(?:licité)?|werb(?:ung)?|广告|Реклама|Anuncio)\z/i.freeze
    LOADING_WORDS = /\A(?:(?:loading|正在加载|Загрузка|chargement|cargando)(?:…|\.\.\.)?)\z/i.freeze

    def initialize(node, content_length, paragraph_keys)
      @node = node
      @text = Dom.text(node)
      @weight = Scorer.cleaning_weight(node)
      @content_length = content_length
      @paragraph_keys = paragraph_keys
    end

    def remove?
      return false if majority? || data_table_involved? || Dom.ancestors_named(@node, "code", "pre").any?
      return true if @weight.negative?
      return false if @text.count(",") >= 10 || video_embed?
      return true if @text.match?(AD_WORDS) || @text.match?(LOADING_WORDS)

      suspicious? && !image_gallery?
    end

    private

    # Page builders (Elementor, Divi) wrap whole articles in "widget" and
    # "module" containers; class weight alone must not delete the article.
    def majority?
      @text.length > @content_length * 0.5
    end

    def data_table_involved?
      return true if @node.name == "table" && Tables.data_table?(@node)

      (Dom.ancestors_named(@node, "table") + @node.css("table").to_a).any? { |table| Tables.data_table?(table) }
    end

    def video_embed?
      @node.css("object, embed, iframe").any? do |embed|
        embed.attribute_nodes.any? { |attribute| attribute.value.to_s.match?(Preprocessor::VIDEO_HOSTS) }
      end
    end

    def suspicious?
      too_many_images? || too_many_list_items? || too_many_inputs? || short_with_links? ||
        too_linky? || suspicious_embeds? || no_text_containers?
    end

    def too_many_images?
      !figure_child? && images > 1 && paragraphs.fdiv(images) < 0.5
    end

    def too_many_list_items?
      !list? && @node.css("li").size - 100 > paragraphs
    end

    def too_many_inputs?
      @node.css("input").size > paragraphs / 3
    end

    def short_with_links?
      !list? && !figure_child? && density(HEADINGS) < 0.9 && @text.length < 25 &&
        (images.zero? || images > 2) && link_density.positive?
    end

    def too_linky?
      (!list? && @weight < 25 && link_density > 0.2) || (@weight >= 25 && link_density > 0.5)
    end

    def suspicious_embeds?
      embeds = @node.css("object, embed, iframe").size
      (embeds == 1 && @text.length < 75) || embeds > 1
    end

    def no_text_containers?
      images.zero? && density(TEXTISH, own_text_length).zero?
    end

    # Galleries survive as long as every list item is a single image.
    def image_gallery?
      list? && @node.element_children.none? { |item| item.element_children.size > 1 } && images == @node.css("li").size
    end

    def paragraphs
      @paragraphs ||= @node.css("p").size + @node.css("div").count { |div| @paragraph_keys.include?(Dom.key(div)) }
    end

    def images
      @images ||= @node.css("img").size
    end

    def list?
      return @list if defined?(@list)

      @list = %w[ul ol].include?(@node.name) || density("ul, ol") > 0.9
    end

    def figure_child?
      return @figure_child if defined?(@figure_child)

      @figure_child = Dom.ancestors_named(@node, "figure").any?
    end

    def link_density
      @link_density ||= begin
        linked = @node.css("a").sum do |anchor|
          weight = anchor["href"].to_s.start_with?("#") ? Stats::FRAGMENT_LINK_WEIGHT : 1.0
          Dom.text(anchor).length * weight
        end
        @text.empty? ? 0.0 : linked / @text.length
      end
    end

    def density(selector, extra = 0)
      return 0.0 if @text.empty?

      (@node.css(selector).sum { |child| Dom.text(child).length } + extra).fdiv(@text.length)
    end

    # Readability wraps a container's loose text in <p>, which then counts as text.
    def own_text_length
      loose = @node.children.reject { |child| child.element? && Dom::PARAGRAPH_BREAKERS.include?(child.name) }
      Dom.squish(loose.map(&:content).join).length
    end
  end
end

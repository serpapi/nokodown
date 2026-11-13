# frozen_string_literal: true

module Nokodown
  # Readability's conditional cleaning for one container: what it holds (link
  # density, images per paragraph, inputs, embeds) decides whether it is prose
  # or page furniture.
  class ContainerCheck
    HEADINGS = "h1, h2, h3, h4, h5, h6"
    TEXTISH = "span, li, td, blockquote, dl, div, img, ol, p, pre, table, ul"
    TEXTISH_NAMES = Set.new(TEXTISH.split(", ")).freeze
    AD_WORDS = /\A(?:ad(?:vertising|vertisement)?|pub(?:licité)?|werb(?:ung)?|广告|Реклама|Anuncio)\z/i.freeze
    LOADING_WORDS = /\A(?:(?:loading|正在加载|Загрузка|chargement|cargando)(?:…|\.\.\.)?)\z/i.freeze
    POST_BODY_SHARE = 0.8
    PLAYER_CLASS = /media/.freeze
    PLAYERS = "video, audio"
    EMBEDS = "object, embed, iframe"

    def initialize(node, content_length, paragraph_keys, memo = {})
      @node = node
      @text = Dom.text(node)
      @content_length = content_length
      @paragraph_keys = paragraph_keys
      @memo = memo
    end

    def self.forget(memo, node)
      memo.delete(:tables) if node.name == "table" || node.at_css("table") || Dom.ancestors_named(node, "table").any?
      memo.delete(:posts) if Dom.thread?(node)
    end

    def remove?
      return false if majority? || forum_post?

      tables, code = Dom.ancestors_named(@node, "table", "code", "pre").partition { |ancestor| ancestor.name == "table" }
      return false if code.any? || data_table_involved?(tables)
      return true if weight.negative?
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

    # "media" in a class is Readability's sign of social-media widgets, but on
    # a container holding a player it names the player.
    def weight
      @weight ||= Scorer.cleaning_weight(@node, ignore: (PLAYER_CLASS if player?))
    end

    def data_table_involved?(outer_tables)
      return true if (@node.name == "table" && data_table?(@node)) || holders_of_data_tables.include?(Dom.key(@node))

      outer_tables.any? { |table| data_table?(table) }
    end

    def holders_of_data_tables
      tables = (@memo[:tables] ||= {})
      tables[:holders] ||= @memo.fetch(:root, @node).css("table").each_with_object(Set.new) do |table, keys|
        next unless data_table?(table)

        keys << Dom.key(table)
        table.ancestors.each { |ancestor| keys << Dom.key(ancestor) if ancestor.element? }
      end
    end

    def data_table?(table)
      verdicts = ((@memo[:tables] ||= {})[:verdicts] ||= {})
      key = Dom.key(table)
      verdicts.key?(key) ? verdicts[key] : (verdicts[key] = Tables.data_table?(table))
    end

    def post_length(post)
      lengths = (@memo[:posts] ||= {})
      lengths[Dom.key(post)] ||= Dom.text(post).length
    end

    def forum_post?
      return false unless Dom.thread?(@node)
      return true if Dom.thread_post?(@node)

      post = @node.ancestors.find { |ancestor| ancestor.element? && Dom.thread_post?(ancestor) }
      !post.nil? && @text.length >= post_length(post) * POST_BODY_SHARE
    end

    # Native players the preprocessor kept play a file, so they are content.
    def player?
      return @player if defined?(@player)

      @player = !none_in_root?(PLAYERS) && !@node.at_css(PLAYERS).nil?
    end

    # Most roots hold no player, embed, input, image or list item. Asking the
    # root once spares asking each container in it; removing containers
    # never adds any. A check without a root asks its own node.
    def none_in_root?(selector)
      root = @memo[:root]
      return false unless root

      absent = (@memo[:absent] ||= {})
      absent.fetch(selector) { absent[selector] = root.at_css(selector).nil? }
    end

    def video_embed?
      return true if player?

      embeds.any? do |embed|
        embed.attribute_nodes.any? { |attribute| Preprocessor.video_embed?(attribute.value) }
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
      list_items > 100 && !list? && list_items - 100 > paragraphs
    end

    def too_many_inputs?
      return false if none_in_root?("input")

      inputs = @node.css("input").size
      inputs.positive? && inputs > paragraphs / 3
    end

    def short_with_links?
      @text.length < 25 && !list? && !figure_child? && density(HEADINGS) < 0.9 &&
        (images.zero? || images > 2) && link_density.positive?
    end

    def too_linky?
      (!list? && weight < 25 && link_density > 0.2) || (weight >= 25 && link_density > 0.5)
    end

    def suspicious_embeds?
      count = embeds.size
      (count == 1 && @text.length < 75) || count > 1
    end

    # No text in the container's own runs or in any text container. A child
    # holding text answers before the subtree is searched.
    def no_text_containers?
      return false unless images.zero?
      return true if @text.empty?
      return false unless own_text_length.zero?

      child = @node.first_element_child
      while child
        return false if TEXTISH_NAMES.include?(child.name) && !Dom.text(child).empty?

        child = child.next_element
      end
      @node.css(TEXTISH).all? { |container| Dom.text(container).empty? }
    end

    # Galleries survive as long as every list item is a single image.
    def image_gallery?
      list? && @node.element_children.none? { |item| item.element_children.size > 1 } && images == list_items
    end

    def paragraphs
      @paragraphs ||= @node.css("p").size + @node.css("div").count { |div| @paragraph_keys.include?(Dom.key(div)) }
    end

    def embeds
      @embeds ||= none_in_root?(EMBEDS) ? [] : @node.css(EMBEDS)
    end

    def list_items
      @list_items ||= none_in_root?("li") ? 0 : @node.css("li").size
    end

    def images
      @images ||= none_in_root?("img") ? 0 : @node.css("img").size
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
      loose = Dom.children(@node).reject { |child| child.element? && Dom::PARAGRAPH_BREAKERS.include?(child.name) }
      Dom.squish(loose.map(&:content).join).length
    end
  end
end

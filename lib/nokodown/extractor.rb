# frozen_string_literal: true

module Nokodown
  class Extractor
    TITLE_SIMILARITY = 0.75
    OPENING_PROSE = 150
    MIN_ARTICLE_LENGTH = 500
    CONDITIONAL_SHARE = 0.5
    REMOVED_LINK_SHARE = 0.5

    def initialize(html, url: nil, main_content: true, title: true, images: true, links: true)
      @html = html
      @url = url
      @main_content = main_content
      @title = title
      @images = images
      @links = links
    end

    def call
      doc = Nokolexbor::HTML(Charset.utf8(@html.to_s))
      metadata = Metadata.new(doc).to_h
      urls = UrlResolver.new(@url, doc.at_css("base[href]")&.[]("href"))
      body = doc.at_css("body")
      return result([], metadata, :none) if body.nil?

      product_page = @main_content && ProductReviews.product_page?(doc, metadata[:page_type])
      Preprocessor.new(body).call
      nodes, mode = select_content(body, metadata[:page_type], product_page, urls)
      blocks = render(nodes, mode, urls)
      blocks = with_title(blocks, metadata[:title]) if @title
      result(blocks, metadata, mode)
    end

    private

    def render(nodes, mode, urls)
      redundant = redundant_images(nodes, mode, urls)
      renderer = Markdown::Renderer.new(urls, images: @images, links: @links, redundant_images: redundant)
      Markdown::Cleanup.call(renderer.render(nodes), renderer.rendered_images)
    end

    # Converting the whole page keeps every visible image.
    def redundant_images(nodes, mode, urls)
      return {} if mode == :full || !@images

      Markdown::RedundantImages.new(nodes, mode, urls).call
    end

    def select_content(body, page_type, product_page, urls)
      return [[body], :full] unless @main_content

      attribution = PostAttribution.new(body).call if ContentLocator::DISCUSSIONS.include?(page_type)
      Boilerplate.new(body).call
      ProductReviews.new(body).call if product_page
      teasers = Teasers.new(body, @url, urls).call
      selection = ContentLocator.new(body, page_type: page_type).call
      attribution&.write(selection.nodes)
      return [Teasers.strip(cleaned_article(selection.nodes, page_type), teasers), :article] if selection.mode == :article

      Pruner.new(selection.nodes, :page).call
      [Teasers.strip(selection.nodes, teasers), :page]
    end

    # Like Readability, fall back to lighter cleaning when conditional cleaning
    # throws away most of what it sees; markup made of many small linky blocks
    # (React apps, card grids) trips it, and a short intro would otherwise pass
    # for the article. When almost nothing is left at all, the content is
    # pruned like a page. Cleaning runs on a copy so it can be undone.
    def cleaned_article(nodes, page_type)
      copies = nodes.map(&:dup)
      pruner = Pruner.new(copies, :article).call
      if almost_nothing_kept?(copies, nodes)
        Pruner.new(nodes, :page).call
        return nodes
      end
      return copies if keep_conditional_cleaning?(pruner, page_type)

      Pruner.new(nodes, :article, conditional: false).call
      nodes
    end

    # When what conditional cleaning removed from a declared article is mostly
    # links, it was a grid of teasers for other stories, not the article. On
    # listings and hubs the same teasers are the content.
    def keep_conditional_cleaning?(pruner, page_type)
      return true if pruner.conditional_share >= CONDITIONAL_SHARE

      page_type == :article && pruner.removed_link_share > REMOVED_LINK_SHARE
    end

    def almost_nothing_kept?(copies, nodes)
      kept = copies.sum { |node| Dom.text(node).length }
      kept < MIN_ARTICLE_LENGTH && kept < nodes.sum { |node| Dom.text(node).length } * 0.25
    end

    # One H1 at the top: the page's own if the content opens with one,
    # otherwise the metadata title, replacing a near-duplicate heading right
    # below it.
    # Nothing found stays empty, so a script-rendered shell or a bot wall does
    # not pass for a page; Result#title still has the title.
    def with_title(blocks, title)
      return blocks if blocks.empty?

      first_h1 = blocks.find { |block| block.kind == :heading && block.level == 1 }
      return demote_h1s(blocks, first_h1) if first_h1 && (title.nil? || page_heading?(blocks, first_h1, title))
      return blocks if title.nil?

      duplicate = blocks.first(3).find do |block|
        block.kind == :heading && Dom.similarity(title, Markdown::Cleanup.heading_text(block)) > TITLE_SIMILARITY
      end
      rest = demote_h1s(blocks.reject { |block| block.equal?(duplicate) }, nil)
      [Markdown::Block.new(:heading, "# #{Markdown::Text.escape(title)}", 1)] + rest
    end

    # When the page's title block is left out of the content, the first H1
    # left can be a section heading below the body's opening paragraphs. A
    # headline may follow a caption or a promo line, but not the body.
    def page_heading?(blocks, h1, title)
      return true if Dom.similarity(title, Markdown::Cleanup.heading_text(h1)) > TITLE_SIMILARITY

      opening = blocks.take_while { |block| !block.equal?(h1) }.select { |block| block.kind == :paragraph }
      opening.sum { |block| Markdown::Text.plain(block.text).length } < OPENING_PROSE
    end

    def demote_h1s(blocks, keep)
      blocks.each do |block|
        next unless block.kind == :heading && block.level == 1 && !block.equal?(keep)

        block.text = "##{block.text}"
        block.level = 2
      end
    end

    def result(blocks, metadata, mode)
      Result.new(
        markdown: blocks.map(&:text).join("\n\n"),
        title: metadata[:title],
        byline: metadata[:byline],
        excerpt: metadata[:excerpt] || first_paragraph(blocks),
        site_name: metadata[:site_name],
        published_time: metadata[:published_time],
        lang: metadata[:lang],
        mode: mode
      )
    end

    def first_paragraph(blocks)
      paragraphs = blocks.select { |block| block.kind == :paragraph }.map { |block| Markdown::Text.plain(block.text) }
      paragraphs.find { |text| text.length >= 80 } || paragraphs.find { |text| !text.empty? }
    end
  end
end

# frozen_string_literal: true

module Nokodown
  class Extractor
    TITLE_SIMILARITY = 0.75
    MIN_ARTICLE_LENGTH = 500

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

      product_page = ProductReviews.product_page?(doc, metadata[:page_type])
      Preprocessor.new(body).call
      nodes, mode = select_content(body, metadata[:page_type], product_page)
      blocks = Markdown::Cleanup.call(Markdown::Renderer.new(urls, images: @images, links: @links).render(nodes))
      blocks = with_title(blocks, metadata[:title]) if @title
      result(blocks, metadata, mode)
    end

    private

    def select_content(body, page_type, product_page)
      return [[body], :full] unless @main_content

      Boilerplate.new(body).call
      ProductReviews.new(body).call if product_page
      selection = ContentLocator.new(body, page_type: page_type).call
      return [cleaned_article(selection.nodes), :article] if selection.mode == :article

      Pruner.new(selection.nodes, :page).call
      [selection.nodes, :page]
    end

    # Like Readability, fall back to light cleaning when conditional cleaning
    # leaves almost nothing; markup made of many small linky blocks (React
    # apps, card grids) trips it. Cleaning runs on a copy so it can be undone.
    def cleaned_article(nodes)
      copies = nodes.map(&:dup)
      Pruner.new(copies, :article).call
      kept = copies.sum { |node| Dom.text(node).length }
      return copies if kept >= MIN_ARTICLE_LENGTH || kept >= nodes.sum { |node| Dom.text(node).length } * 0.25

      Pruner.new(nodes, :page).call
      nodes
    end

    # One H1 at the top: the page's own if the content has one, otherwise the
    # metadata title, replacing a near-duplicate heading right below it.
    def with_title(blocks, title)
      first_h1 = blocks.find { |block| block.kind == :heading && block.level == 1 }
      return demote_h1s(blocks, first_h1) if first_h1
      return blocks if title.nil?

      duplicate = blocks.first(3).find do |block|
        block.kind == :heading && Dom.similarity(title, Markdown::Cleanup.heading_text(block)) > TITLE_SIMILARITY
      end
      [Markdown::Block.new(:heading, "# #{Markdown::Text.escape(title)}", 1)] + blocks.reject { |block| block.equal?(duplicate) }
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

# frozen_string_literal: true

require "nokolexbor"

require_relative "nokodown/version"
require_relative "nokodown/charset"
require_relative "nokodown/dom"
require_relative "nokodown/stats"
require_relative "nokodown/patterns"
require_relative "nokodown/tables"
require_relative "nokodown/url_resolver"
require_relative "nokodown/metadata"
require_relative "nokodown/preprocessor"
require_relative "nokodown/post_attribution"
require_relative "nokodown/boilerplate"
require_relative "nokodown/product_reviews"
require_relative "nokodown/scorer"
require_relative "nokodown/content_locator"
require_relative "nokodown/container_check"
require_relative "nokodown/pruner"
require_relative "nokodown/markdown/text"
require_relative "nokodown/markdown/image"
require_relative "nokodown/markdown/code_block"
require_relative "nokodown/markdown/inline"
require_relative "nokodown/markdown/redundant_images"
require_relative "nokodown/markdown/table"
require_relative "nokodown/markdown/renderer"
require_relative "nokodown/markdown/cleanup"
require_relative "nokodown/markdown/image_cleanup"
require_relative "nokodown/result"
require_relative "nokodown/extractor"

module Nokodown
  # Extracts the content of an HTML page as Markdown, plus page metadata.
  #
  #   result = Nokodown.extract(html, url: "https://example.com/post")
  #   result.markdown
  #   result.title
  #
  # Options:
  #   url:          page URL, used to resolve relative links and images
  #   main_content: true (default) keeps only the main content; false converts
  #                 the whole page, removing only invisible elements and scripts
  #   title:        prepend the page title as an H1 when the content has none;
  #                 a page with no content gives empty Markdown, not the title
  #   images:       include images
  #   links:        keep links; false renders link text only
  def self.extract(html, **options)
    Extractor.new(html, **options).call
  end

  def self.to_markdown(html, **options)
    extract(html, **options).markdown
  end
end

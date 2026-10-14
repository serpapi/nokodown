# frozen_string_literal: true

require "nokolexbor"

require_relative "readable_markdown/version"
require_relative "readable_markdown/charset"
require_relative "readable_markdown/dom"
require_relative "readable_markdown/stats"
require_relative "readable_markdown/patterns"
require_relative "readable_markdown/tables"
require_relative "readable_markdown/url_resolver"
require_relative "readable_markdown/metadata"
require_relative "readable_markdown/preprocessor"
require_relative "readable_markdown/boilerplate"
require_relative "readable_markdown/scorer"
require_relative "readable_markdown/content_locator"
require_relative "readable_markdown/container_check"
require_relative "readable_markdown/pruner"
require_relative "readable_markdown/markdown/text"
require_relative "readable_markdown/markdown/image"
require_relative "readable_markdown/markdown/code_block"
require_relative "readable_markdown/markdown/inline"
require_relative "readable_markdown/markdown/table"
require_relative "readable_markdown/markdown/renderer"
require_relative "readable_markdown/markdown/cleanup"
require_relative "readable_markdown/result"
require_relative "readable_markdown/extractor"

module ReadableMarkdown
  # Extracts the content of an HTML page as Markdown, plus page metadata.
  #
  #   result = ReadableMarkdown.extract(html, url: "https://example.com/post")
  #   result.markdown
  #   result.title
  #
  # Options:
  #   url:          page URL, used to resolve relative links and images
  #   main_content: true (default) keeps only the main content; false converts
  #                 the whole page, removing only invisible elements and scripts
  #   title:        prepend the page title as an H1 when the content has none
  #   images:       include images
  #   links:        keep links; false renders link text only
  def self.extract(html, **options)
    Extractor.new(html, **options).call
  end

  def self.to_markdown(html, **options)
    extract(html, **options).markdown
  end
end

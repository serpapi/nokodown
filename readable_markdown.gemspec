# frozen_string_literal: true

require_relative "lib/readable_markdown/version"

Gem::Specification.new do |spec|
  spec.name = "readable_markdown"
  spec.version = ReadableMarkdown::VERSION
  spec.authors = ["SerpApi"]
  spec.summary = "Clean, low-noise Markdown from any web page"
  spec.description = "Extracts the main content of articles, listings, product pages, docs and every other kind of " \
                     "web page as Markdown, with Readability-style metadata. Built on Nokolexbor."
  spec.homepage = "https://github.com/serpapi/readable_markdown"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 2.7"

  spec.files = Dir["lib/**/*.rb", "LICENSE", "NOTICE", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "nokolexbor", ">= 0.6"
end

# frozen_string_literal: true

require_relative "lib/nokodown/version"

Gem::Specification.new do |spec|
  spec.name = "nokodown"
  spec.version = Nokodown::VERSION
  spec.authors = ["SerpApi"]
  spec.summary = "Clean, low-noise Markdown from any web page"
  spec.description = "Extracts the main content of articles, listings, product pages, docs and every other kind of " \
                     "web page as Markdown, with Readability-style metadata. Built on Nokolexbor."
  spec.homepage = "https://github.com/serpapi/nokodown"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 2.7"

  spec.files = Dir["lib/**/*.rb", "CHANGELOG.md", "LICENSE", "NOTICE", "README.md"]
  spec.require_paths = ["lib"]

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.add_dependency "nokolexbor", "~> 0.6"
end

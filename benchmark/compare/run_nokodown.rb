# frozen_string_literal: true

# Writes nokodown's Markdown for every WCXB page: OUT/<split>/md/<id>.md.
#
#   ruby benchmark/compare/run_nokodown.rb WCXB_DIR OUT_DIR [baseline]
#
# With "baseline", it converts the main-region baseline instead: the page's
# <main>, else its only <article>, else <body>, without main-content
# detection.

require "fileutils"
require "json"
require "zlib"
require_relative "../../lib/nokodown"

def main_region(html, url)
  doc = Nokolexbor::HTML(Nokodown::Charset.utf8(html))
  articles = doc.css("article")
  region = doc.at_css("main") || (articles.size == 1 ? articles.first : nil) || doc.at_css("body")
  return "" unless region

  Nokodown.to_markdown("<html>#{doc.at_css('head')&.to_html}<body>#{region.to_html}</body></html>", url: url, main_content: false)
end

wcxb, out, mode = ARGV
abort "usage: ruby run_nokodown.rb WCXB_DIR OUT_DIR [baseline]" unless wcxb && out

%w[dev test].each do |split|
  FileUtils.mkdir_p(File.join(out, split, "md"))
  Dir[File.join(wcxb, split, "ground-truth", "*.json")].sort.each do |path|
    id = File.basename(path, ".json")
    url = JSON.parse(File.read(path))["url"]
    html = Zlib::GzipReader.open(File.join(wcxb, split, "html", "#{id}.html.gz"), &:read)
    markdown = mode == "baseline" ? main_region(html, url) : Nokodown.to_markdown(html, url: url)
    File.write(File.join(out, split, "md", "#{id}.md"), markdown)
  end
end

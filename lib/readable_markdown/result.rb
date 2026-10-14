# frozen_string_literal: true

module ReadableMarkdown
  # mode is :article when the page was narrowed to one body of prose, :page
  # when the whole main region was kept, :full when main_content was off and
  # :none when the document had no body.
  Result = Struct.new(:markdown, :title, :byline, :excerpt, :site_name, :published_time, :lang, :mode, keyword_init: true)
end

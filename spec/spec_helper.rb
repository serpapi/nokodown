# frozen_string_literal: true

require "readable_markdown"

RSpec.configure do |config|
  config.expect_with(:rspec) { |expectations| expectations.syntax = :should }
  config.mock_with(:rspec) { |mocks| mocks.syntax = :should }
  config.order = :random
end

def fixture(name)
  File.read(File.join(__dir__, "fixtures", name))
end

# Converts a fragment without main-content detection or a prepended title,
# so a spec sees exactly what the renderer made of its markup.
def convert(html, **options)
  ReadableMarkdown.to_markdown("<body>#{html}</body>", url: "https://example.com/dir/page", main_content: false, title: false, **options)
end

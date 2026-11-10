# frozen_string_literal: true

require "nokodown"

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
  Nokodown.to_markdown("<body>#{html}</body>", url: "https://example.com/dir/page", main_content: false, title: false, **options)
end

# Renders a fragment like #convert, then tidies it as main content is:
# repeats, quotes of earlier posts, stray rules and images shown twice go.
def convert_content(html)
  body = Nokolexbor::HTML("<body>#{html}</body>").at_css("body")
  Nokodown::Preprocessor.new(body).call
  renderer = Nokodown::Markdown::Renderer.new(Nokodown::UrlResolver.new("https://example.com/dir/page"))
  Nokodown::Markdown::Cleanup.call(renderer.render([body]), renderer.rendered_images).map(&:text).join("\n\n")
end

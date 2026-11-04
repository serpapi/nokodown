# frozen_string_literal: true

RSpec.describe Nokodown::UrlResolver do
  let(:urls) { described_class.new("https://example.com/dir/page?utm_source=x") }

  it "gives the same answer when asked again for a link, an image or an anchor" do
    2.times do
      urls.resolve("/a?utm_source=feed&id=1").should == "https://example.com/a?id=1"
      urls.resolve_image("/img.jpg?w=300").should == "https://example.com/img.jpg"
      urls.same_page?("https://example.com/dir/page#top").should == true
      urls.same_page?("https://example.com/dir/other#top").should == false
      urls.resolve("  ").should be_nil
    end
  end

  it "is not changed by changes to a string it was given or returned" do
    href = +"/a"
    first = urls.resolve(href)
    href << "b"

    first.should be_frozen
    urls.resolve("/a").should == "https://example.com/a"
    urls.resolve(href).should == "https://example.com/ab"
  end
end

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

  it "reads a URL as a browser does, in linear time" do
    described_class.normalize(" \x01 java\tscript:x\n \x7F").should == "javascript:x \x7F"
    described_class.normalize(" \x05\t").should == ""

    url = "/a#{' ' * 50_000}b"
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    described_class.normalize(" #{url} ").should == url
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).should < 0.5
  end

  it "reads a URL with visible ends without searching it" do
    searches = 0
    trace = TracePoint.new(:c_call) { |point| searches += 1 if %i[index rindex].include?(point.method_id) }

    trace.enable { described_class.normalize("/a\tb?c=d\n#e").should == "/ab?c=d#e" }

    searches.should == 0
    described_class.normalize("é/ü").should == "é/ü"
    described_class.normalize("/a ").should == "/a"
    -> { described_class.normalize("/a\xFF".dup.force_encoding("UTF-8")) }.should raise_error(ArgumentError)
  end

  it "is not changed by changes to a string it was given or returned" do
    href = +"/a"
    first = urls.resolve(href)
    href << "b"

    first.should be_frozen
    urls.resolve("/a").should == "https://example.com/a"
    urls.resolve(href).should == "https://example.com/ab"
  end

  it "unwraps each known click redirector, and the same paths on other hosts are kept" do
    target = "https%3A%2F%2Fexample.org%2Fdoc"
    redirectors = %w[
      https://www.google.co.uk/url?q= https://youtube.com/redirect?q= https://lm.facebook.com/l.php?u= https://l.facebook.com/l.php?u=
      https://eur01.safelinks.protection.outlook.com/?url= https://go.redirectingat.com?url=
      https://redirect.viglink.com/?u= https://click.linksynergy.com/deeplink?murl=
      https://www.avantlink.com/click.php?url= https://shop.pxf.io/c/1/2/3?u= https://www.kqzyfj.com/click-1-2?url=
      https://steamcommunity.com/linkfilter/?url=
    ]
    redirectors.each { |href| urls.resolve("#{href}#{target}").should == "https://example.org/doc" }

    kept = %w[
      https://example.com/www.google.com/url?q= https://mygoogle.com/url?q= https://youtube.com/redirect/x?q=
      https://safelinks.protection.outlook.com.example/?url= https://xgo.skimresources.com/?url=
      https://www.avantlink.com/click.php/x?url= https://kqzyfj.com/click?url=
    ]
    kept.each { |href| urls.resolve("#{href}#{target}").should == "#{href}#{target}" }
  end

  it "finds anchors to the page only in URLs with a fragment" do
    urls.same_page?("https://example.com/dir/page").should == false
    urls.same_page?("https://example.com/dir/page#").should == true
    urls.same_page?("mailto:a@example.com#x").should == false
  end

  it "encodes only the characters a URL cannot hold" do
    urls.resolve("/a b/é?x=<1>&y=[2]#|").should == "https://example.com/a%20b/%C3%A9?x=%3C1%3E&y=%5B2%5D#%7C"
    urls.resolve("/é|").should == "https://example.com/%C3%A9%7C"
    urls.resolve("/a-b._~:@!$&'()*+,;=%41").should == "https://example.com/a-b._~:@!$&'()*+,;=%41"
  end
end

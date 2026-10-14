# frozen_string_literal: true

RSpec.describe Nokodown::Metadata do
  def metadata(head, body = "")
    Nokodown::Metadata.new(Nokolexbor::HTML("<html><head>#{head}</head><body>#{body}</body></html>")).to_h
  end

  it "prefers JSON-LD article data" do
    json = { "@context" => "https://schema.org", "@graph" => [
      { "@type" => "WebSite", "name" => "Site" },
      { "@type" => "BlogPosting", "headline" => "From JSON-LD", "datePublished" => "2026-01-02",
        "author" => [{ "name" => "Ada" }, { "name" => "Grace" }], "publisher" => { "name" => "Example Press" } }
    ] }
    result = metadata(%(<title>Other</title><script type="application/ld+json">#{JSON.generate(json)}</script>))

    result[:title].should == "From JSON-LD"
    result[:byline].should == "Ada, Grace"
    result[:published_time].should == "2026-01-02"
    result[:site_name].should == "Example Press"
    result[:page_type].should == :article
  end

  it "ignores malformed JSON-LD" do
    metadata(%(<title>Plain title here</title><script type="application/ld+json">{oops</script>))[:title].should == "Plain title here"
  end

  it "reads Open Graph and other meta tags" do
    result = metadata(<<~HTML)
      <meta property="og:title" content="Open Graph Title">
      <meta property="og:site_name" content="Example">
      <meta name="author" content="Lin">
      <meta name="description" content="A description &amp;amp; more">
      <meta property="article:published_time" content="2026-03-04T05:06:07Z">
      <meta property="og:type" content="product">
    HTML

    result[:title].should == "Open Graph Title"
    result[:byline].should == "Lin"
    result[:excerpt].should == "A description & more"
    result[:published_time].should == "2026-03-04T05:06:07Z"
    result[:page_type].should == :product
  end

  it "removes the site name from the title" do
    metadata(%(<title>Release notes | Example</title><meta property="og:site_name" content="Example">))[:title].should == "Release notes"
  end

  it "keeps the whole title when cutting it would leave too little" do
    metadata("<title>Pricing | Example Corp</title>")[:title].should == "Pricing | Example Corp"
  end

  it "keeps the H1's part of the title, dropping sections, site names and keywords" do
    metadata("<title>Using the Widget API - Web APIs | Example Docs</title>", "<main><h1>Using the Widget API</h1></main>")[:title]
      .should == "Using the Widget API"
    metadata('<meta property="og:title" content="Do Smart Thermostats Save Money? | Heating, Cooling and Air Quality">', "<h1>Do smart thermostats save money?</h1>")[:title]
      .should == "Do Smart Thermostats Save Money?"
  end

  it "keeps the title when the H1 only matches its first words" do
    metadata('<meta property="og:title" content="Trail Running Shoes for Women">', "<h1>Trail Running</h1>")[:title].should == "Trail Running Shoes for Women"
  end

  it "does not take a logo H1 that links home for the page's name" do
    metadata('<meta property="og:title" content="Example Corp | Industrial Widgets">', '<header><h1><a href="/">Example Corp</a></h1></header>')[:title]
      .should == "Example Corp | Industrial Widgets"
  end

  it "drops a book's name that an H1 outside the main content repeats at the end of the title" do
    body = '<div class="menu-bar"><h1 class="menu-title">The Example Book</h1></div><main><h2>Understanding Ownership Rules</h2></main>'

    metadata("<title>Understanding Ownership Rules - The Example Book</title>", body)[:title].should == "Understanding Ownership Rules"
    metadata("<title>Example Search Weekly | State of Search</title>", "<article><h1>State of Search</h1></article>")[:title]
      .should == "Example Search Weekly | State of Search"
  end

  it "uses the document byline and language when there is no metadata" do
    result = metadata("<title>Post title with enough words</title>", '<p class="byline">By Sam Rivera</p>')

    result[:byline].should == "Sam Rivera"
    Nokodown.extract('<html lang="pt-BR"><p>Olá</p></html>').lang.should == "pt-BR"
  end
end

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

  it "reads a forum thread's opening post like an article but types the page as a forum" do
    json = { "@type" => "DiscussionForumPosting", "headline" => "Starter smells like acetone", "author" => { "name" => "wren" } }
    result = metadata(%(<title>Other</title><script type="application/ld+json">#{JSON.generate(json)}</script>))

    result[:title].should == "Starter smells like acetone"
    result[:byline].should == "wren"
    result[:page_type].should == :forum
  end

  it "detects forums from nested JSON-LD, microdata or the forum software" do
    nested = { "@type" => "WebPage", "mainEntity" => { "@type" => "DiscussionForumPosting", "headline" => "Thread" } }

    metadata(%(<script type="application/ld+json">#{JSON.generate(nested)}</script>))[:page_type].should == :forum
    metadata("", '<div itemscope itemtype="https://schema.org/DiscussionForumPosting"></div>')[:page_type].should == :forum
    metadata('<meta name="generator" content="Discourse 3.4.0 - https://github.com/discourse/discourse">')[:page_type].should == :forum
  end

  it "keeps a news article whose reader comments are forum postings an article" do
    json = { "@type" => "NewsArticle", "headline" => "Council votes", "comment" => [{ "@type" => "DiscussionForumPosting", "text" => "Shame" }] }
    microdata = '<article itemscope itemtype="https://schema.org/NewsArticle"><div itemprop="comment" itemscope itemtype="https://schema.org/DiscussionForumPosting"></div></article>'

    metadata(%(<script type="application/ld+json">#{JSON.generate(json)}</script>))[:page_type].should == :article
    metadata('<meta property="og:type" content="article">', microdata)[:page_type].should == :article
  end

  it "detects Q&A pages" do
    json = { "@type" => "QAPage", "mainEntity" => { "@type" => "Question", "name" => "Why is RAID not a backup?" } }

    metadata(%(<script type="application/ld+json">#{JSON.generate(json)}</script>))[:page_type].should == :qa
    metadata("", '<div itemscope itemtype="https://schema.org/QAPage"></div>')[:page_type].should == :qa
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

  it "takes an H1 whose permalink links to the page itself for the page's name" do
    body = '<h1>Using the Widget API <a href="#using-the-widget-api">¶</a></h1>'

    metadata("<title>Using the Widget API - Web APIs | Example Docs</title>", body)[:title].should == "Using the Widget API"
  end

  it "keeps the title when the H1 only matches its first words" do
    metadata('<meta property="og:title" content="Trail Running Shoes for Women">', "<h1>Trail Running</h1>")[:title].should == "Trail Running Shoes for Women"
  end

  it "does not cut at a slash, which also joins words within a name" do
    metadata("<title>Rock / Pop Music Store Online</title>", "<h1>Rock</h1>")[:title]
      .should == "Rock / Pop Music Store Online"
  end

  it "matches an H1 whose letters change length when downcased" do
    metadata("<title>İstanbul Gezi Rehberi | Örnek Site</title>", "<h1>İstanbul Gezi Rehberi</h1>")[:title]
      .should == "İstanbul Gezi Rehberi"
  end

  it "does not take a logo H1 for the page's name" do
    title = "Example Corp | Industrial Widgets"
    head = %(<meta property="og:title" content="#{title}">)

    metadata(head, '<header><h1><a href="/">Example Corp</a></h1></header>')[:title].should == title
    metadata(head, '<h1><a href="https://example.com/index.html">Example Corp</a></h1>')[:title].should == title
    metadata(head, '<h1><a href="/en-us/">Example Corp</a></h1>')[:title].should == title
    metadata(head, '<h1><a href="/?ref=logo">Example Corp</a></h1>')[:title].should == title
    metadata(head, '<header><h1 class="site-title">Example Corp</h1></header>')[:title].should == title
  end

  it "drops a book's name that its H1 repeats at the end of the title when the rest is a heading" do
    body = '<div class="menu-bar"><h1 class="menu-title">The Example Book</h1></div><main><h2>Understanding Ownership Rules</h2></main>'

    metadata("<title>Understanding Ownership Rules - The Example Book</title>", body)[:title].should == "Understanding Ownership Rules"
  end

  it "takes a heading in the article's own header for the page's name" do
    body = "<header><h1>The Example Baking Blog</h1></header><article><header><h2>How to Bake Bread</h2></header></article>"

    metadata("<title>How to Bake Bread - The Example Baking Blog</title>", body)[:title].should == "How to Bake Bread"
  end

  it "keeps a 'Site | Page' title whose site name is not a heading" do
    metadata("<title>City of Springfield | Parks and Recreation</title>", "<div><h1>Parks and Recreation</h1></div>")[:title]
      .should == "City of Springfield | Parks and Recreation"
  end

  it "keeps a 'Site | Page' title whose site name is a heading of fewer than 3 words" do
    metadata("<title>Acme | Contact Us</title>", "<div><h1>Contact Us</h1></div><aside><h3>Acme</h3></aside>")[:title]
      .should == "Acme | Contact Us"
  end

  it "keeps a 'Site | Page' title whose site name is an H1, a logo, or a heading in the site's header or footer" do
    title = "City of Springfield | Parks and Recreation"
    page = "<main><h1>Parks and Recreation</h1></main>"
    site_headings = [
      '<header><h1 class="site-title"><a href="/">City of Springfield</a></h1></header>',
      '<div class="masthead"><h2 class="site-name">City of Springfield</h2></div>',
      "<footer><h3>City of Springfield</h3></footer>"
    ]

    site_headings.each { |site| metadata("<title>#{title}</title>", site + page)[:title].should == title }
    metadata("<title>City of Springfield » Parks and Recreation</title>", "<div><h1>City of Springfield</h1></div>#{page}")[:title]
      .should == "City of Springfield » Parks and Recreation"
  end

  it "does not match an H1 without words to the end of a title without words" do
    body = '<h1><img src="/logo.png" alt=""></h1><h2>Understanding Ownership Rules</h2>'

    metadata("<title>Understanding Ownership Rules - ★★★</title>", body)[:title].should == "Understanding Ownership Rules - ★★★"
  end

  it "uses the document byline and language when there is no metadata" do
    result = metadata("<title>Post title with enough words</title>", '<p class="byline">By Sam Rivera</p>')

    result[:byline].should == "Sam Rivera"
    Nokodown.extract('<html lang="pt-BR"><p>Olá</p></html>').lang.should == "pt-BR"
  end
end

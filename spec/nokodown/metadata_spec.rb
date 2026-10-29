# frozen_string_literal: true

RSpec.describe Nokodown::Metadata do
  def metadata(head, body = "")
    metadata_at(nil, head, body)
  end

  def metadata_at(url, head, body = "")
    Nokodown::Metadata.new(Nokolexbor::HTML("<html><head>#{head}</head><body>#{body}</body></html>"), url).to_h
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

  it "decodes the named entities left in metadata values" do
    json = { "@type" => "Article", "headline" => "Lot B, Kitchener: MLS&reg; #1038 &ndash; Caf&eacute; &lt;3" }

    metadata(%(<script type="application/ld+json">#{JSON.generate(json)}</script>))[:title].should == "Lot B, Kitchener: MLS® #1038 – Café <3"
  end

  it "decodes only entities that end with a semicolon" do
    json = { "@type" => "Article", "headline" => "Search?q=tea&copy=1 &ndash; Shop" }

    metadata(%(<script type="application/ld+json">#{JSON.generate(json)}</script>))[:title].should == "Search?q=tea&copy=1 – Shop"
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

  it "does not cut at an underscore inside a file name" do
    metadata("<title>install_guide_linux</title>", "<h1>install</h1>")[:title].should == "install_guide_linux"
  end

  it "does not cut at a slash, which also joins words within a name" do
    metadata("<title>Rock / Pop Music Store Online</title>", "<h1>Rock</h1>")[:title]
      .should == "Rock / Pop Music Store Online"
  end

  it "matches an H1 whose letters change length when downcased" do
    metadata("<title>İstanbul Gezi Rehberi | Örnek Site</title>", "<h1>İstanbul Gezi Rehberi</h1>")[:title]
      .should == "İstanbul Gezi Rehberi"
  end

  it "drops a logo H1's name from the title instead of taking it for the page's name" do
    head = '<meta property="og:title" content="Example Corp | Industrial Widgets">'

    metadata(head, '<header><h1><a href="/">Example Corp</a></h1></header>')[:title].should == "Industrial Widgets"
    metadata(head, '<h1><a href="https://example.com/index.html">Example Corp</a></h1>')[:title].should == "Industrial Widgets"
    metadata(head, '<h1><a href="/en-us/">Example Corp</a></h1>')[:title].should == "Industrial Widgets"
    metadata(head, '<h1><a href="/?ref=logo">Example Corp</a></h1>')[:title].should == "Industrial Widgets"
    metadata(head, '<header><h1 class="site-title">Example Corp</h1></header>')[:title].should == "Industrial Widgets"
  end

  it "does not take a wiki page's H1 that links to index.php for the site's name" do
    body = '<h1><a href="index.php?Ownership%20Rules">Ownership Rules</a></h1>'

    metadata("<title>Ownership Rules - Example Wiki</title>", body)[:title].should == "Ownership Rules"
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

  it "keeps a 'Site | Page' title whose site name is a plain H1 or a heading in the site's header or footer" do
    title = "City of Springfield | Parks and Recreation"
    page = "<main><h1>Parks and Recreation</h1></main>"
    site_headings = [
      '<div class="masthead"><h2 class="site-name">City of Springfield</h2></div>',
      "<footer><h3>City of Springfield</h3></footer>"
    ]

    site_headings.each { |site| metadata("<title>#{title}</title>", site + page)[:title].should == title }
    metadata("<title>City of Springfield » Parks and Recreation</title>", "<div><h1>City of Springfield</h1></div>#{page}")[:title]
      .should == "City of Springfield » Parks and Recreation"
  end

  it "drops the site's name as its domain spells it from either end of the title" do
    url = "https://www.gta-series.com/it/armi.html"

    metadata_at(url, "<title>Fucili d'assalto - GTA-Series.com</title>")[:title].should == "Fucili d'assalto"
    metadata_at(url, "<title>GTA-Series.com | Fucili d'assalto</title>")[:title].should == "Fucili d'assalto"
  end

  it "drops a last part that mentions the domain" do
    title = "Hotels in Coclé | Find great deals and compare on trivago"

    metadata_at("https://www.trivago.ae/en-AE/odr/hotels-cocle", %(<meta property="og:title" content="#{title}">))[:title]
      .should == "Hotels in Coclé"
  end

  it "keeps title words that are a short domain's name by chance" do
    metadata_at("https://www.in.gov/dor/tax-forms/", '<meta property="og:title" content="Tax Forms for Businesses in Indiana">', "<h1>Tax Forms</h1>")[:title]
      .should == "Tax Forms for Businesses in Indiana"
    metadata_at("https://www.nu.nl/binnenland/6312/storm.html", '<meta property="og:title" content="Storm raast over het land - wat je nu moet weten">')[:title]
      .should == "Storm raast over het land - wat je nu moet weten"
  end

  it "drops a last part that names a short domain as an acronym" do
    metadata_at("https://www.jec.com.br/noticias/ingressos", "<title>Ingressos à venda | JEC - Joinville Esporte Clube</title>")[:title]
      .should == "Ingressos à venda"
    metadata_at("https://ia.ca/savings-plans", "<title>Our Savings Plans | iA Financial Group</title>")[:title].should == "Our Savings Plans"
  end

  it "drops the start of a declared site name that goes on with a slogan" do
    head = '<meta property="og:title" content="Rachmaninov MK2 RCA Cable - Sound Glory - Hi-Fi Store">' \
           '<meta property="og:site_name" content="Sound Glory - Hi-Fi Store - Serving music lovers since 1986">'

    metadata(head)[:title].should == "Rachmaninov MK2 RCA Cable"
  end

  it "cuts the site's name from a title of thousands of parts in linear time" do
    parts = Array.new(3000) { |index| "cheap flights #{index}" }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    title = metadata_at("https://www.example.com/travel/deals", "<title>#{parts.join(' | ')} | Example.com</title>")[:title]

    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).should < 2
    title.should == parts.join(" | ")
  end

  it "takes the last part of a breadcrumb title that the site's name leads" do
    metadata_at("http://www.gta-series.com/it/gta-5/armi.html", "<title>GTA-Series.com » GTA 5 » Armi » Fucili d'assalto</title>")[:title]
      .should == "Fucili d'assalto"
  end

  it "keeps the page's own separators after a breadcrumb that the site's name leads" do
    metadata_at("https://acme-blog.com/2020/rust/", "<title>Acme Blog » Blog Archive » Why we moved to Rust - Part 2</title>")[:title]
      .should == "Why we moved to Rust - Part 2"
    metadata_at("https://ppag.pl/dzien-1/", "<title>PPAG » Dzień 1 – Aby urosnąć, trzeba obumrzeć</title>")[:title]
      .should == "Dzień 1 – Aby urosnąć, trzeba obumrzeć"
  end

  it "takes the <title> when the declared title only names the site" do
    head = '<meta property="og:title" content="Seongnam Library"><title>Seongnam Library > Notices > Card spending report</title>'

    metadata(head, '<h1 class="header-logo"><a href="/sn/index.do">Seongnam Library</a></h1>')[:title].should == "Card spending report"
  end

  it "keeps the site's name in the title of its home page" do
    metadata_at("https://hughlupton.com/", "<title>Hugh Lupton - Storyteller</title>")[:title].should == "Hugh Lupton - Storyteller"
  end

  it "keeps the site's name in the title of a language's home page" do
    metadata_at("https://hughlupton.com/en/", "<title>Hugh Lupton - Storyteller</title>")[:title].should == "Hugh Lupton - Storyteller"
  end

  it "cuts the title after the H1's words at an underscore or before the site's name" do
    metadata("<title>60级副本任务介绍_网络游戏水浒Q传_新浪游戏_新浪网</title>", "<h1>60级副本任务介绍</h1>")[:title].should == "60级副本任务介绍"
    metadata_at("https://www.eventernote.com/events", "<title>June 2016 events and lives Eventernote</title>", "<h1>June 2016 events and lives</h1>")[:title]
      .should == "June 2016 events and lives"
  end

  it "takes the H1 that the URL names when the title does not" do
    url = "https://np-arbeitssicherheit.de/schulung/1850002-geruestnutzer-pflichtunterweisung-e-learning-input-2-0.html"
    head = "<title>PSA gegen Absturz – Jährliche Pflichtunterweisung</title>"

    metadata_at(url, head, "<h1>1850002 Gerüstnutzer - Pflichtunterweisung E-Learning / iNPut 2.0</h1>")[:title]
      .should == "1850002 Gerüstnutzer - Pflichtunterweisung E-Learning / iNPut 2.0"
  end

  it "reads a line break in the H1 as a space between its words" do
    url = "https://example.com/es/sectores/maquinas-de-cafe-para-caterings"
    body = "<h1>Máquinas de café<br><span>para caterings</span></h1>"

    metadata_at(url, "<title>Coffee machines for catering | WMF</title>", body)[:title].should == "Máquinas de café para caterings"
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

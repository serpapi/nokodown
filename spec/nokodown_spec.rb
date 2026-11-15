# frozen_string_literal: true

require "zlib"

RSpec.describe Nokodown do
  describe ".extract" do
    it "returns the markdown with the page metadata" do
      result = Nokodown.extract(fixture("article.html"), url: "https://example.com/tidal")

      result.markdown.should start_with("# How Tidal Power Plants Store Energy\n\nTidal lagoons hold water")
      result.title.should == "How Tidal Power Plants Store Energy"
      result.byline.should == "Mara Lindqvist"
      result.excerpt.should == "Lagoons, barrages and turbines that run in both directions."
      result.site_name.should == "Coastal Engineering Weekly"
      result.published_time.should == "2026-09-30T08:00:00Z"
      result.lang.should == "en"
      result.mode.should == :article
    end

    it "returns empty markdown for an empty document" do
      Nokodown.extract("").markdown.should == ""
    end

    it "reports :none for a frameset page, which has no body" do
      result = Nokodown.extract('<html><head><title>Frames</title></head><frameset><frame src="a.html"></frameset></html>')

      result.mode.should == :none
      result.markdown.should == ""
      result.title.should == "Frames"
    end

    it "returns empty markdown, but the title, when the page has no content" do
      result = Nokodown.extract('<title>Dashboard</title><body><div id="app"></div><script src="/app.js"></script></body>')

      result.markdown.should == ""
      result.title.should == "Dashboard"
    end

    it "keeps the headline of a page that has nothing else" do
      html = "<title>Harbour Town Community Forum</title><body><h1>Is the ferry running today?</h1></body>"

      Nokodown.to_markdown(html).should == "# Is the ferry running today?"
    end

    it "keeps every heading of a page made of headings alone" do
      Nokodown.to_markdown("<h1>One</h1><h2>Two</h2><h3>Three</h3>").should == "# One\n\n## Two\n\n### Three"
    end

    it "puts the title above a section H1 that follows the opening paragraphs" do
      intro = "<p>#{'Vertical mice and trackballs spare the wrist in different ways, and we tested both kinds. ' * 3}</p>"
      section = "<p>#{'The first pick suits most hands and works on any desk surface we tried. ' * 3}</p>"
      html = "<title>The Best Ergonomic Mice</title><body><article>#{intro}<h1>Deeper Dive: Our Picks</h1>#{section}</article></body>"

      Nokodown.to_markdown(html).should start_with("# The Best Ergonomic Mice\n\nVertical mice")
      Nokodown.to_markdown(html).should include("\n\n## Deeper Dive: Our Picks\n\n")
    end

    it "keeps the page's headline above an article body chosen inside main" do
      long = "Meaningful sentence with several useful words inside it. " * 10
      page = "<main><div>Breadcrumb trail</div><div><h1>Story</h1><div>Subtitle</div></div>" \
             "<article><p>#{long}</p></article><aside>Related story</aside></main>"

      Nokodown.to_markdown("<body>#{page}</body>").should start_with("# Story\n\nMeaningful sentence")
      Nokodown.to_markdown("<title>Story</title><body>#{page}</body>").should start_with("# Story\n\nMeaningful sentence")
      Nokodown.to_markdown("<title>Story</title><body>#{page}</body>", title: false).should start_with("Meaningful sentence")
    end

    it "keeps the page's own headline below a photo caption" do
      body = "<p>#{'Yamada earned its first star this year, and twelve more places joined the list. ' * 3}</p>"
      html = "<title>Michelin Restaurants in New York on Resy</title><body><article>" \
             "<p>Photo by Ben Hon for Resy</p><h1>The Resy Guide to the Michelin Winners</h1>#{body}</article></body>"

      Nokodown.to_markdown(html).should start_with("Photo by Ben Hon for Resy\n\n# The Resy Guide to the Michelin Winners")
    end

    it "accepts nil" do
      Nokodown.extract(nil).markdown.should == ""
    end

    it "falls back to the first paragraph for the excerpt" do
      html = "<title>Notes</title><p>Short.</p><p>#{'A sentence long enough to describe the page. ' * 3}</p>"

      Nokodown.extract(html).excerpt.should start_with("A sentence long enough")
    end
  end

  describe ".to_markdown" do
    it "returns just the markdown" do
      Nokodown.to_markdown("<title>Hello</title><p>World</p>").should == "# Hello\n\nWorld"
    end
  end

  describe "large result sets" do
    # NodeSet#each wraps its nodes one at a time from Ruby; to_a wraps them
    # all in C, which takes about two thirds of the time.
    it "are read as Arrays by the passes that walk most of the page" do
      walkers = []
      Nokolexbor::NodeSet.any_instance.stub(:each).and_wrap_original do |original, *args, &block|
        frame = caller_locations.find { |location| location.path.include?("/lib/nokodown/") }
        walkers << "#{File.basename(frame.path, '.rb')}##{frame.label.sub('block in ', '')}" if frame
        original.call(*args, &block)
      end
      %w[article.html docs.html forum.html listing.html].each do |name|
        [true, false].each { |main_content| Nokodown.to_markdown(fixture(name), url: "https://example.com/", main_content: main_content) }
      end

      hot = %w[preprocessor#call preprocessor#remove_hidden dom#paragraph_keys dom#shared_keys? heading_anchors#mark
               metadata#meta_values pruner#remove_related_links pruner#remove_stray_lines pruner#link_text_length
               pruner#remove_suspicious_containers pruner#remove_boilerplate_text pruner#remove_calls_to_action
               scorer#phrasing_runs scorer#scoring_parent container_check#own_text_length]
      (walkers.uniq & hot).should == []
    end
  end

  describe "cleanup of the main content" do
    def extract(html)
      Nokodown.to_markdown(html, url: "https://example.com/page", title: false)
    end

    let(:prose) { "<p>#{'The command line tool runs on every major platform and needs nothing else to work. ' * 3}</p>" }

    it "keeps the link lists of an index page, which are its content" do
      sections = {
        "A" => %w[Anatomy Astronomy Architecture Art], "B" => %w[Biology Botany Banking Baking],
        "C" => %w[Chemistry Climate Cooking Crafts], "D" => %w[Dentistry Design Drama Diving]
      }
      html = sections.map do |letter, topics|
        "<h2>#{letter}</h2><ul>#{topics.map { |topic| "<li><a href=\"/topics/#{topic.downcase}\">#{topic}</a></li>" }.join}</ul>"
      end.join

      markdown = extract("<main><h1>Topics A-Z</h1>#{html}</main>")

      markdown.should include("## A\n\n- [Anatomy](https://example.com/topics/anatomy)")
      markdown.should include("- [Diving](https://example.com/topics/diving)")
    end

    it "drops the few menu links left in a content area that holds almost nothing else" do
      html = '<main><a href="#content">Skip to content</a><div><a href="/shop">Shop all products</a> ' \
             '<a href="/help">Help and contact</a> <a href="/account">Your account</a></div><p>Sold out.</p></main>'

      markdown = extract(html)

      markdown.should include("Sold out.")
      ["Shop all", "Help and", "Your account"].each { |noise| markdown.should_not include(noise) }
    end

    it "drops a footer sitemap even when it holds most of the text" do
      links = %w[Autoscaling Networking Postgres Disks Previews Deploys Workers Cron Blog Docs Pricing Careers Status]
      footer = "<footer><ul>#{links.map { |link| "<li><a href=\"/#{link.downcase}\">#{link}</a></li>" }.join}</ul></footer>"

      markdown = extract("<main><h1>The cloud for builders</h1><p>Deploy in minutes.</p>#{footer}</main>")

      markdown.should include("Deploy in minutes.")
      markdown.should_not include("Autoscaling")
    end

    it "drops the cart controls of product cards and the links beside them" do
      categories = '<div><a href="/c/cups">Cups</a> <a href="/c/jugs">Jugs</a> <a href="/c/bowls">Bowls</a></div>'
      card = '<li><a href="/p/mug"><img src="/mug.jpg" alt="Stoneware mug"><h2>Stoneware mug</h2></a><span>$18</span>' \
             '<div class="actions"><a class="button" href="/cart/add?id=1">Add to cart</a> <span>Quick view</span></div></li>'

      markdown = extract("<main><h1>Mugs</h1>#{categories}<ul>#{card * 3}</ul></main>")

      markdown.should include("## [Stoneware mug](https://example.com/p/mug)\n\n  $18")
      ["Cups", "Add to cart", "Quick view"].each { |noise| markdown.should_not include(noise) }
    end

    it "drops links styled as buttons" do
      html = "<article>#{prose}<div><a class=\"btn btn-primary\" href=\"/signup\">Sign up now</a> " \
             "<a class=\"btn\" href=\"/demo\">Book a demo</a></div>#{prose}</article>"

      markdown = extract(html)

      markdown.should_not include("Sign up now")
      markdown.should_not include("Book a demo")
    end

    it "keeps buttons that hold a number, a download or a card's only link" do
      html = <<~HTML
        <article>#{prose}
          <div class="mover"><h3>Lone Star Movers</h3><p>Long distance moves.</p><a href="/movers/lone-star">Profile</a> <span class="btn">Call (734) 338-1828</span></div>
          <p>Annual report <a href="/reports/2023">Summary</a> <a class="btn btn-sm" href="/reports/2023.pdf">PDF</a></p>
          <div class="recipe"><h3>Lemon tart</h3><p>Sharp and sweet, with a shortcrust base, lemon curd and a crisp sugar top that takes an hour.</p><a class="btn" href="/recipes/lemon-tart">Get the recipe</a></div>
        </article>
      HTML

      markdown = extract(html)

      markdown.should include("Call (734) 338-1828")
      markdown.should include("[PDF](https://example.com/reports/2023.pdf)")
      markdown.should include("[Get the recipe](https://example.com/recipes/lemon-tart)")
    end

    it "drops a button after a heading, a group of buttons and links with role=button" do
      html = <<~HTML
        <article>#{prose}
          <section><h2>Ship faster</h2>#{prose}<a href="/docs">Read the docs</a> <a class="c-button" href="/start">Get started</a></section>
          <div><a class="btn" href="/mac">Download for Mac</a> / <a class="btn" href="/windows">Download for Windows</a> / <a class="btn" href="/linux">Download for Linux</a></div>
          <div><a role="button" href="/trial">Start a free trial</a></div>
        </article>
      HTML

      markdown = extract(html)

      ["Get started", "Download for", "Start a free trial"].each { |noise| markdown.should_not include(noise) }
    end

    it "keeps a button inside a sentence and buttons in data tables" do
      html = <<~HTML
        <article>#{prose}
          <p>Use the <span><a class="btn btn-sm" href="/download">Download</a></span> button to get the installer for your system.</p>
          <table><tr><th>Plan</th><th>Price</th><th>Order</th></tr><tr><td>Solo</td><td>$5</td><td><a class="btn" href="/buy">Buy</a></td></tr></table>
        </article>
      HTML

      markdown = extract(html)

      markdown.should include("Use the [Download](https://example.com/download) button")
      markdown.should include("| Solo | $5 | [Buy](https://example.com/buy) |")
    end

    it "keeps disclosure toggles and the labels inside them" do
      html = <<~HTML
        <article>#{prose}
          <div><a role="button" aria-expanded="false" href="#shipping">Shipping and returns</a></div>
          <div><a class="btn" aria-controls="sizes" href="#sizes">Size guide</a></div>
          <div><a class="btn" href="#offline">Does it work offline?</a></div>
          <div><a class="btn accordion-toggle" href="#warranty">Warranty</a></div>
          <div><a href="#care" aria-expanded="false"><span class="button">Care instructions</span></a></div>
          #{prose}
        </article>
      HTML

      markdown = extract(html)

      ["Shipping and returns", "Size guide", "Does it work offline?", "Warranty", "Care instructions"].each do |label|
        markdown.should include(label)
      end
    end

    it "keeps titles, terms, footnote markers and names that are styled as buttons" do
      authors = { "ada" => "Ada Lovelace", "alan" => "Alan Turing", "grace" => "Grace Hopper" }
      html = <<~HTML
        <article>
          <h1>KALLAX Shelf unit, <span><a role="button" href="/kallax?size=30x57">30x57</a></span></h1>
          <p>The sessions ran every week.<sup><a role="button" href="#fn1">1</a></sup> And they kept going.</p>#{prose}
          <h3><a class="btn btn-link" href="/jobs/elixir">Elixir Observability Engineer</a></h3>
          <dl><dt><a role="button" href="#ingredients">Ingredients</a></dt><dd>Sugar, pectin and citric acid.</dd></dl>
          <ul>#{authors.map { |slug, name| "<li><a class=\"btn-view-author-options\" href=\"/authors/#{slug}\">#{name}</a></li>" }.join}</ul>
        </article>
      HTML

      markdown = extract(html)

      markdown.should include("# KALLAX Shelf unit, [30x57](https://example.com/kallax?size=30x57)")
      markdown.should include("every week.1 And")
      markdown.should include("### [Elixir Observability Engineer](https://example.com/jobs/elixir)")
      markdown.should include("- **Ingredients**: Sugar")
      markdown.should include("- [Alan Turing](https://example.com/authors/alan)")
    end

    it "keeps the text of links that blocks cut into copies" do
      html = "<article><h1>Title</h1><p>#{'Introduction, important body text. ' * 10}</p><div><a href=\"/x\">" \
             "<div>Details, useful content, and more.</div><section><span>Supplement, helpful text about this.</span></a></section></div></article>"
      markdown = extract(html)
      markdown.should include("Details, useful content, and more.")
      markdown.should include("Supplement, helpful text about this.")

      html = "#{'Intro. ' * 80}<a href=/s><p>#{'Lead. ' * 160}<div><img src=/i.jpg alt=I><article>#{'TAIL. ' * 80}<a href=/s>"
      extract(html).should include("TAIL. TAIL.")
    end

    it "keeps highlighted code whose tokens look like page furniture" do
      html = "<article>#{prose}<pre><code class=\"language-python\"><span class=\"nb\">print</span>(x)</code></pre>#{prose}</article>"

      extract(html).should include("```python\nprint(x)\n```")
    end
  end

  describe "main_content: false" do
    it "keeps navigation, headers and footers" do
      markdown = Nokodown.to_markdown(fixture("article.html"), url: "https://example.com/", main_content: false)

      markdown.should include("[News](https://example.com/news)")
      markdown.should include("3 comments")
      markdown.should include("Tidal lagoons hold water")
    end

    it "still drops scripts, hidden elements and form controls" do
      html = "<p>Visible</p><script>alert(1)</script><p hidden>Hidden</p><div style='display: none'>Gone</div><input value='x'>"

      Nokodown.extract(html, main_content: false, title: false).markdown.should == "Visible"
    end

    it "reports :full mode" do
      Nokodown.extract("<p>x</p>", main_content: false).mode.should == :full
    end
  end

  describe "accordions and tabs" do
    def article(widget)
      Nokodown.to_markdown("<title>Trail stove</title><article><h1>Trail stove</h1><p>#{'It boils a litre in three minutes. ' * 6}</p>#{widget}</article>")
    end

    it "keeps a closed accordion panel that a button opens" do
      html = '<button aria-controls="faq-1" aria-expanded="false">Do you ship abroad?</button>' \
             '<div id="faq-1" class="accordion-panel" aria-hidden="true"><p>Yes, to most of Europe.</p></div>'

      convert(html).should == "Do you ship abroad?\n\nYes, to most of Europe."
    end

    it "keeps a closed accordion panel hidden by style that its header controls" do
      html = '<h3 id="ship-q"><button aria-controls="ship-a" aria-expanded="false">Do you ship abroad?</button></h3>' \
             '<div id="ship-a" role="region" aria-labelledby="ship-q" style="display:none"><p>Yes, to most of Europe.</p></div>'

      convert(html).should == "### Do you ship abroad?\n\nYes, to most of Europe."
    end

    it "keeps a closed tab panel labelled by its tab" do
      convert('<div role="tabpanel" aria-labelledby="tab-2" aria-hidden="true"><p>Weighs 85 g.</p></div>').should == "Weighs 85 g."
    end

    it "drops aria-hidden icons and the full copy behind a read-more link" do
      html = '<p><span class="icon" aria-hidden="true">★</span> Used, with light wear on the ... ' \
             '<span class="expandable-text" aria-hidden="true">Used, with light wear on the cover.</span></p>'

      convert(html).should == "Used, with light wear on the ..."
    end

    it "drops a strip of tab labels" do
      article('<ul role="tablist"><li role="tab">Specifications</li><li role="tab">Reviews</li></ul>').should_not include("Specifications")
    end

    it "keeps a tab list wrapped around its panels" do
      markdown = article('<div role="tablist"><ul><li role="tab">Specifications</li></ul><div role="tabpanel"><p>Weighs 85 g.</p></div></div>')

      markdown.should include("Weighs 85 g.")
    end

    it "keeps an FAQ marked up as a tab list" do
      answer = "No. It only takes screw-on canisters of isobutane and propane, sold at most outdoor shops. " * 3
      markdown = article("<div role='tablist'><h2>Can it burn white gas?</h2><p>#{answer}</p></div>")

      markdown.should include("## Can it burn white gas?\n\nNo. It only takes")
    end
  end

  describe "hidden content" do
    it "places React streamed segments where their templates are, without the loading fallback" do
      html = '<div><h2>Index funds</h2><!--$?--><template id="B:0"></template><div>Loading paragraph...</div><!--/$-->' \
             '<p>Fees matter.</p></div><div hidden id="S:0"><p>An index fund tracks a market index.</p></div>'

      convert(html).should == "## Index funds\n\nAn index fund tracks a market index.\n\nFees matter."
    end

    it "removes a loading fallback that holds a boundary of its own" do
      html = '<h1>Index funds</h1><!--$?--><template id="B:0"></template><p>Loading the article.</p>' \
             '<!--$--><p>Loading the chart.</p><!--/$--><p>Still loading.</p><!--/$--><p>Fees matter.</p>' \
             '<div hidden id="S:0"><p>An index fund tracks a market index.</p></div>'

      convert(html).should == "# Index funds\n\nAn index fund tracks a market index.\n\nFees matter."
    end

    it "places a streamed segment whose id would break a selector" do
      html = '<h1>Index funds</h1><template id="P:1\']"></template><div hidden id="S:1\']"><p>An index fund tracks a market index.</p></div>' \
             '<div hidden id="S:\\"><p>Never placed.</p></div>'

      convert(html).should == "# Index funds\n\nAn index fund tracks a market index."
    end

    it "leaves a streamed segment made of links hidden, as it is without scripts" do
      cards = [["Camp kettle", "19.99"], ["Titanium pot set", "39.99"], ["Folding windscreen", "12.50"]].map do |name, price|
        "<div><a href=\"/p/#{name.downcase.tr(' ', '-')}\"><h3>Trailhead #{name}</h3></a><span>€#{price}</span></div>"
      end
      html = '<h1>Trail stove</h1><template id="P:0"></template><template id="P:1"></template>' \
             '<div hidden id="S:0"><p>Boils a litre in three minutes on <a href="/fuel">isobutane</a>.</p></div>' \
             "<div hidden id=\"S:1\"><h2>More from Trailhead</h2>#{cards.join}</div>"

      convert(html).should == "# Trail stove\n\nBoils a litre in three minutes on [isobutane](https://example.com/fuel)."
    end

    it "drops elements Webflow hides when their condition fails" do
      convert('<p>Open daily.</p><div class="w-condition-invisible"><p>Closed for the holidays.</p></div>').should == "Open daily."
    end

    it "drops a large hidden block beside the visible title, but not an anti-flicker wrapper around the page" do
      article = "<h1>Trail stoves</h1><p>#{'A trail stove boils a litre in three minutes. ' * 14}</p>"
      copy = "<pre hidden>#{'# Trail stoves raw markdown copy of the article. ' * 8}</pre>"

      convert(article + copy).should_not include("raw markdown copy")
      convert("<div style='visibility:hidden'>#{article}</div>").should include("boils a litre")
    end

    it "keeps an anti-flicker wrapper when only the site logo's h1 is outside it" do
      article = "<h1>Trail stoves</h1><p>#{'A trail stove boils a litre in three minutes. ' * 14}</p>"
      logos = ["<h1><a href='/'>Trailhead</a></h1>", "<a href='https://example.com/en/'><h1>Trailhead</h1></a>",
               "<h1><img src='/logo.png' alt='Trailhead'></h1>", "<nav><h1>Trailhead</h1></nav>"]

      logos.each do |logo|
        convert("<header>#{logo}</header><div style='display:none'>#{article}</div>").should include("boils a litre")
      end
      convert("<h1><a href='/stoves'>Stoves</a></h1><div style='display:none'>#{article}</div>").should_not include("boils a litre")
    end
  end

  describe "title: false" do
    it "does not prepend the metadata title" do
      markdown = Nokodown.to_markdown(fixture("article.html"), title: false)

      markdown.should start_with("Tidal lagoons hold water")
    end
  end

  describe "images: false" do
    it "drops images but keeps emoji" do
      markdown = convert('<p><img src="/a.png" alt="Chart"> Done <img class="emoji" alt="✅" src="/e.png"></p>', images: false)

      markdown.should == "Done ✅"
    end
  end

  describe "links: false" do
    it "keeps link text only" do
      convert('<p>Read <a href="/docs">the docs</a>.</p>', links: false).should == "Read the docs."
    end
  end

  describe "conditional cleaning" do
    def story(extra)
      paragraphs = [
        "Tidal lagoons hold water behind a wall at high tide, then release it through turbines once the sea has dropped, which lets operators time their output to demand.",
        "Unlike a run-of-river dam, a lagoon can pump extra water in at high tide using surplus grid power, and recover it later, because the head is larger on the way out.",
        "Bulb turbines in modern barrages generate on both the flood and the ebb tide, and reversing the blade pitch keeps the mechanical design simple and efficient.",
        "Sihwa Lake in South Korea and La Rance in France are the largest schemes in operation, and both have run for decades with modest maintenance costs."
      ]
      html = "<title>Tides</title><body><article><h1>Tides</h1>#{paragraphs.map { |text| "<p>#{text}</p>" }.join}#{extra}</article></body>"
      Nokodown.to_markdown(html, title: false)
    end

    ["rounded-xl overflow-hidden", "field field--label-hidden", "product__description quick-add-hidden"].each do |classes|
      it "keeps prose in a container classed #{classes}" do
        markdown = story(%(<div class="#{classes}"><p>Lagoon walls are built from rock and sand.</p><p>Sluice gates let the sea in.</p><p>Fish pass through slow turbines.</p></div>))

        markdown.should include("Lagoon walls are built from rock and sand.\n\nSluice gates let the sea in.\n\nFish pass through slow turbines.")
      end
    end

    it "keeps a heading whose anchor holds a negative class word" do
      markdown = story('<h2 id="h-media-coverage-of-tidal-lagoons">Media coverage of tidal lagoons</h2><p>Newspapers mostly covered the cost.</p>')

      markdown.should include("## Media coverage of tidal lagoons")
    end

    describe "a heading anchor on an element the parser repeats" do
      def guide(article)
        paragraphs = (1..12).map { |i| "<p>Paragraph #{i} of the story has enough words in it to be read as running text by any extractor, and then some more.</p>" }
        Nokodown.to_markdown("<html><head><title>Guide</title></head><body><article>#{article}#{paragraphs.join}</article></body></html>")
      end

      it "keeps the article when the anchor is left open in a heading inside a heading" do
        markdown = guide('<h1><div><h2><b id="social-media">Social media</h2></div>Social media</h1>')

        markdown.should include("Paragraph 1 of the story")
        markdown.should include("Paragraph 12 of the story")
      end

      it "keeps the article when the anchor is left open around a streamed segment holding the heading" do
        markdown = guide('<div><b id="social-media"><template id="B:1"></template></div><div hidden id="S:1"><h2>Social media</h2></div>')

        markdown.should include("## Social media\n\nParagraph 1 of the story")
        markdown.should include("Paragraph 12 of the story")
      end
    end

    it "still drops comments whose heading carries a permalink" do
      markdown = story('<section id="comments"><h2>Comments<a href="#comments">¶</a></h2><p>Jane wrote: the turbine part was the clearest.</p></section>')

      markdown.should_not include("Comments")
      markdown.should_not include("Jane wrote")
    end

    it "still drops copies shown only at some screen sizes" do
      markdown = story('<div class="hidden sm:block"><p>Wide screen copy of the intro.</p></div><div class="md:hidden"><p>Narrow screen copy of the intro.</p></div>')

      markdown.should include("modest maintenance costs.")
      markdown.should_not include("copy of the intro")
    end
  end

  describe "articles split into blocks" do
    def block(heading, topic, count)
      paragraphs = Array.new(count) { |index| "<p>#{topic} matters for a working parent, and part #{index + 1} explains why, with an example or two.</p>" }
      "<div class='block html'><div class='block-content'><div class='text-block'><div class='html-content'>#{heading}#{paragraphs.join}</div></div></div></div>"
    end

    it "keeps every block of the body, not only the longest" do
      body = block("", "Balance", 10) + "<div class='block image'><img src='/desk.jpg' alt=''></div>" +
             block("<h2>Release perfection</h2>", "Letting go", 4) + block("<h2>Stop multitasking</h2>", "Focus", 4)
      html = "<head><title>Balance</title><meta property='og:type' content='article'></head>" \
             "<body><main><article><h1>Balance</h1><div class='row'><div class='col'>#{body}</div></div></article></main></body>"

      markdown = Nokodown.to_markdown(html)
      markdown.should include("Balance matters for a working parent")
      markdown.should include("## Release perfection")
      markdown.should include("Focus matters for a working parent")
    end

    def band(topic)
      cards = Array.new(3) do |index|
        "<div class='card'><h3>#{topic} #{index + 1}</h3><p>#{topic} shows each campaign on one screen, " \
          "so a falling conversion rate is caught on Monday, not at month end.</p></div>"
      end
      "<div class='band'><div class='container'><div class='row'><h2>#{topic}</h2>#{cards.join}</div></div></div>"
    end

    it "keeps a landing page's other bands when only its sibling sections would make it an article" do
      answers = Array.new(4) do |index|
        "<h3>Question #{index + 1}?</h3><p>Answer #{index + 1} covers search, paid media and email, " \
          "so budgets follow what works and every plan starts with an audit.</p>"
      end
      html = "<title>Harbor Analytics</title><body>" \
             "<div class='hero'><h1>Harbor Analytics</h1><p>We turn the data your campaigns already collect " \
             "into clear weekly decisions that your whole team can act on.</p></div>#{band("Dashboards")}" \
             "<div class='claim'><h2>Teams that measure every channel improve their targeting within a quarter.</h2>" \
             "<p><a href='/cases'>How we do it</a></p></div>#{band("Reports")}" \
             "<div class='faq'><div class='container'><div class='row'>#{answers.join}</div></div></div></body>"

      markdown = Nokodown.to_markdown(html)
      markdown.should include("We turn the data your campaigns already collect")
      markdown.should include("[How we do it](/cases)")
    end

    it "drops a disclaimer at the end of the body" do
      paragraphs = Array.new(5) { |index| "<p>Index funds track a market index at low cost, and part #{index + 1} explains how.</p>" }
      disclaimer = "<div class='cmp-richtext--disclaimer'><p>Rates are subject to change and are not an offer of credit.</p></div>"
      html = "<title>Index funds</title><body><article><h1>Index funds</h1>#{paragraphs.join}#{disclaimer}</article></body>"

      Nokodown.to_markdown(html).should_not include("subject to change")
    end
  end

  describe "deeply nested markup" do
    # Puma serves requests in threads, whose stack is much smaller than the
    # main thread's.
    def in_thread(&block)
      Thread.new(&block).value
    end

    {
      "blocks" => "<p>Visible</p>#{'<div>' * 3000}Deep#{'</div>' * 3000}",
      "inline elements" => "<p>Visible #{'<span>' * 3000}Deep#{'</span>' * 3000}</p>",
      "lists" => "<p>Visible</p>#{'<ul><li>' * 1500}Deep#{'</li></ul>' * 1500}",
      "links and emphasis" => "<p>Visible</p>#{'<a href="/x"><strong>' * 1500}Deep#{'</strong></a>' * 1500}",
      "tables" => "<p>Visible</p>#{'<table><tr><td>' * 1000}Deep#{'</td></tr></table>' * 1000}",
      "noscript content" => "<p>Hi</p><noscript><p>Visible #{'word ' * 100}</p>#{'<div>' * 3000}Deep#{'</div>' * 3000}</noscript>"
    }.each do |shape, html|
      it "renders #{shape} 3000 levels deep inside a thread" do
        [true, false].each do |main_content|
          in_thread { Nokodown.to_markdown(html, url: "https://example.com/", main_content: main_content) }.should include("Visible", "Deep")
        end
      end
    end

    it "renders 10,000 levels on the main thread" do
      html = "<body>#{%(<div onclick="alert('deep')">) * 10_000}deep#{'</div>' * 10_000}</body>"

      Nokodown.to_markdown(html).should == "deep"
      Nokodown.to_markdown(("<div>" * 4000) + "leaf" + ("</div>" * 4000)).should == "leaf"
    end

    it "keeps the words of flattened elements apart" do
      html = "#{'<div>' * 100}<p>One</p><p>Two<br>Three</p><span>Four</span>#{'</div>' * 100}"

      convert(html).should == "One Two Three Four"
    end

    it "leaves the nesting of real pages alone" do
      html = "#{'<div>' * 60}<h2>Title</h2><p>Some <em>text</em></p>#{'</div>' * 60}"

      convert(html).should == "## Title\n\nSome *text*"
    end
  end

  describe "max_length:" do
    def prose(index)
      "<p>Paragraph #{index} tells how the river rose through the night and the town woke to water in the streets and fields.</p>"
    end

    # The lengths at which max_length does not give the start of the whole
    # conversion, or changes the excerpt.
    def prefix_mismatches(html, lengths, **options)
      whole = Nokodown.extract(html, url: "https://example.com/page", **options)
      lengths.reject do |length|
        cut = Nokodown.extract(html, url: "https://example.com/page", max_length: length, **options)
        cut.markdown == whole.markdown[0, length] && cut.excerpt == whole.excerpt
      end
    end

    # Pages long enough for rendering to stop early, each with something
    # the whole content decides later on: a headline far down, a thumbnail
    # shown again without its link, the excerpt, a list's spacing, a repeat
    # that turns into a run, and a section label in an outline.
    {
      "a late H1" => ["<title>Flood night</title><article>%<prose>s<h1>Flood night</h1>%<one>s</article>", {}],
      "a thumbnail" => ["<article><p><a href='/story'><img src='/photo.jpg'></a> <a href='/story'>Story</a> %<sentence>s</p>%<prose>s<p><img src='/photo.jpg'></p>%<one>s</article>", { title: false }],
      "the excerpt" => ["<body>%<lines>s%<prose>s</body>", { main_content: false, title: false }],
      "a loose list" => ["<head><meta name='description' content='A list'></head><body><ul>%<items>s<li><p>Last</p><p>item</p></li></ul></body>", { main_content: false, title: false }],
      "a repeated run" => ["<article><p>%<long>s</p>%<one>s%<filler>s<p>%<long>s</p>%<one>s%<prose>s</article>", { title: false }],
      "an outline" => ["<head><meta name='description' content='Outline'></head><body><article><h1>Outline</h1>%<headings>s%<one>s</article></body>", { title: false }]
    }.each do |name, (template, options)|
      it "gives the start of the whole conversion of a page with #{name}" do
        html = format(template, prose: Array.new(40) { |index| prose(index) }.join, one: prose(1), long: "x" * 1000, filler: "<p>#{'z' * 90}</p>" * 12,
                                sentence: "The river rose through the night.", lines: Array.new(120) { |index| "<p>Line #{index}</p>" }.join,
                                items: Array.new(120) { |index| "<li>Item #{index}</li>" }.join,
                                headings: Array.new(150) { |index| index == 3 ? "<h2>Tags</h2>" : "<h2>Heading #{index}</h2>" }.join)

        prefix_mismatches(html, (0..3000).step(25), **options).should == []
      end
    end

    it "gives the start of the whole conversion of each fixture" do
      Dir[File.join(__dir__, "fixtures", "*.html")].sort.each do |path|
        html = File.read(path) * 3
        [true, false].each do |main_content|
          [path, prefix_mismatches(html, [0, 1, 40, 300, 1000, 2500, 6000], main_content: main_content)].should == [path, []]
        end
      end
    end

    it "renders long content once, and only its start" do
      html = "<article>#{Array.new(2000) { |index| prose(index) }.join}</article>"
      renderers = []
      Nokodown::Markdown::Renderer.should_receive(:new).once.and_wrap_original do |original, *args, **options|
        original.call(*args, **options).tap { |renderer| renderers << renderer }
      end

      Nokodown.to_markdown(html, max_length: 500).length.should == 500
      renderers.first.should be_cut
    end

    it "reads no more of a long element's children than the budget needs" do
      html = "<article><div>#{Array.new(2000) { |index| "#{prose(index)}<span></span>" }.join}</div></article>"
      longest = 0
      Nokodown::Dom.stub(:children).and_wrap_original do |original, node|
        original.call(node).tap { |children| longest = [longest, children.size].max }
      end

      Nokodown.to_markdown(html, main_content: false, max_length: 500).length.should == 500
      longest.should < 100
    end

    it "changes nothing when nil" do
      html = "<title>Flood night</title><article>#{Array.new(40) { |index| prose(index) }.join}</article>"

      Nokodown.extract(html, max_length: nil).should == Nokodown.extract(html)
    end

    it "gives empty Markdown for 0" do
      Nokodown.to_markdown("<article>#{Array.new(40) { |index| prose(index) }.join}</article>", max_length: 0).should == ""
    end

    it "rejects a negative or non-integer length" do
      -> { Nokodown.extract("<p>x</p>", max_length: -1) }.should raise_error(ArgumentError)
      -> { Nokodown.extract("<p>x</p>", max_length: "50") }.should raise_error(ArgumentError)
    end

    # WCXB=tmp/corpora/wcxb bundle exec rspec checks every WCXB page.
    it "gives the start of the whole conversion of every WCXB page" do
      corpus = ENV["WCXB"]
      skip "set WCXB to a WCXB checkout to run" unless corpus

      Dir[File.join(corpus, "{dev,test}", "html", "*.html.gz")].sort.each do |path|
        html = Zlib::GzipReader.open(path, &:read)
        [true, false].each do |main_content|
          [path, main_content, prefix_mismatches(html, [0, 1000, 5000, 50_000], main_content: main_content)].should == [path, main_content, []]
        end
      end
    end
  end

  describe "attributes named like Nokodown's own" do
    it "ignores a page's element keys outside the body" do
      html = '<html data-nokodown-key="1"><body><div class="post">Y</div><div class="signature">API signature</div></body></html>'
      described_class.to_markdown(html).should == "Y\n\nAPI signature"
    end

    it "ignores a page's root key on a named html element" do
      html = '<html class="post" data-nokodown-key="0"><body><div class="signature">X</div><p>Y</p></body></html>'
      described_class.extract(html).to_h.values_at(:markdown, :excerpt).should == ["Y", "Y"]
    end
  end

  describe "misnested formatting on forum pages" do
    # The copies a misnested <b> leaves share one attribute list, and
    # marking one copy of it as a thread or a replaced panel can drop the
    # key of another.
    let(:reply) { "A burr grinder gives a much more even grind than a blade grinder." }

    it "scores a question whose bold runs into the reply" do
      html = '<html><head><title>Coffee</title><script type="application/ld+json">' \
             '{"@type":"DiscussionForumPosting","headline":"Coffee"}</script></head><body>' \
             "<p>Which grinder do you use for espresso at home? <b class=\"comment-body\">Thanks.</p><p>#{reply}</p></body></html>"
      described_class.to_markdown(html).should ==
        "# Coffee\n\nWhich grinder do you use for espresso at home? **Thanks.**\n\n**#{reply}**"
    end

    it "weighs a reply list whose items share a bold" do
      html = '<meta name="generator" content="vBulletin 5">' \
             "<ul><li><b class=\"box\"></li><li id=\"respond\">Reply<p>#{reply}</p></li></ul>"
      described_class.to_markdown(html).should == "- Reply\n\n  #{reply}"
    end

    it "weighs a reply link that runs into the reply as a link" do
      html = '<meta name="generator" content="vBulletin 5">' \
             "<p>Question? <a class=\"respond\" href=\"#note\"></p>\n<p>#{"Reply. " * 42}"
      described_class.to_markdown(html, title: false).should start_with("Question?\n\nReply. Reply.")
    end

    it "keeps posts whose member panels share a bold" do
      post = lambda do |i|
        %(<div class="post"><div class="header"><span class="username">user#{i}</span> ) +
          %(<time datetime="2024-03-0#{i}">March #{i}, 2024</time></div>) +
          %(<p><b class="postprofile">Member</p><p>Posts: 12</b></p><div class="message"><p>Reply #{i}: #{reply}</p></div></div>)
      end
      html = %(<meta name="generator" content="vBulletin 5">#{post.call(1)}#{post.call(2)})
      described_class.to_markdown(html).should == "**user1** · March 1, 2024\n\nReply 1: #{reply}\n\n" \
                                                  "**user2** · March 2, 2024\n\nReply 2: #{reply}"
    end
  end

  describe "selector order on the article copy" do
    # Lexbor sorts a CSS selector list's results by numbers it writes on the
    # document's nodes, and a copy keeps them, so the queries that run on
    # the page before the article is copied decide later orders.
    it "drops an intro line beside a boilerplate notice" do
      prose = "Useful prose, with details. " * 10
      html = "<section>Intro<p>All rights reserved</p><div></div></section><p>#{prose}</p>"
      described_class.to_markdown(html).should == prose.strip
      described_class.to_markdown(html, max_length: 5).should == "Usefu"
    end

    it "keeps an intro line when the page has ad attributes and misnested formatting" do
      prose = "Useful prose, with details. " * 10
      html = "<i data-ad-slot></i><b><div>misnested <a href=\"/out\">link</b> after</div></a>" \
             "<section>Intro<p>All rights reserved</p></section><p>#{prose}</p>"
      described_class.to_markdown(html).should == "**misnested [link](/out)** [after](/out)\n\nIntro\n\n#{prose.strip}"
      plain = "<ins data-ad-slot=\"1\"></ins><section>Intro<span>All rights reserved</span></section><section>#{prose}</section>"
      described_class.to_markdown(plain).should == "Intro\n\n#{prose.strip}"
    end
  end

  describe "Ruby globals" do
    it "drops separator lines as String#lines finds them under another $/" do
      saved = $/
      begin
        $/ = " "
        result = described_class.extract("<p>alpha --- omega</p>", main_content: false, title: false)
      ensure
        $/ = saved
      end
      result.to_h.values_at(:markdown, :excerpt).should == ["alpha omega", "alpha omega"]
    end
  end

  describe "encodings" do
    it "transcodes binary input using the declared charset" do
      html = "<html><head><meta charset=\"windows-1252\"></head><body><p>caf\xE9</p></body></html>".b

      Nokodown.to_markdown(html, title: false).should == "café"
    end

    it "drops invalid UTF-8 bytes" do
      Nokodown.to_markdown("<p>a\xFFb</p>", title: false).should == "ab"
    end
  end
end

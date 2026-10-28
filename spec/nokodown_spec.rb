# frozen_string_literal: true

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

    it "still drops copies shown only at some screen sizes" do
      markdown = story('<div class="hidden sm:block"><p>Wide screen copy of the intro.</p></div><div class="md:hidden"><p>Narrow screen copy of the intro.</p></div>')

      markdown.should include("modest maintenance costs.")
      markdown.should_not include("copy of the intro")
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

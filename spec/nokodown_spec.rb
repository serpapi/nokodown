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

    it "puts the title above a section H1 that follows the opening paragraphs" do
      intro = "<p>#{'Vertical mice and trackballs spare the wrist in different ways, and we tested both kinds. ' * 3}</p>"
      section = "<p>#{'The first pick suits most hands and works on any desk surface we tried. ' * 3}</p>"
      html = "<title>The Best Ergonomic Mice</title><body><article>#{intro}<h1>Deeper Dive: Our Picks</h1>#{section}</article></body>"

      Nokodown.to_markdown(html).should start_with("# The Best Ergonomic Mice\n\nVertical mice")
      Nokodown.to_markdown(html).should include("\n\n## Deeper Dive: Our Picks\n\n")
    end

    it "keeps the page's own headline below a photo caption" do
      body = "<p>#{'Yamada earned its first star this year, and twelve more places joined the list. ' * 3}</p>"
      html = "<title>Michelin Restaurants in New York on Resy</title><body><article>" \
             "<p>Photo by Ben Hon for Resy</p><h1>The Resy Guide to the Michelin Winners</h1>#{body}</article></body>"

      Nokodown.to_markdown(html).should start_with("Photo by Ben Hon for Resy\n\n# The Resy Guide to the Michelin Winners")
    end

    it "puts the page's title in place of a heading that only names the site" do
      body = "<p>#{'We caught twelve trout at the upper pond, and the water was cold and clear all day. ' * 3}</p>"
      html = "<title>Bonten Fishing Pond - Friends from afar</title><body><article>" \
             "<h1><a href='http://bonten.example/'>Bonten Fishing Pond</a></h1>#{body}</article></body>"

      Nokodown.to_markdown(html, url: "http://bonten.example/calendar/671515").should start_with("# Friends from afar\n\nWe caught")
    end

    it "puts the title above a section's name when the URL names the title" do
      body = "<h1>Transparencia</h1><p>Reporte abril 2023</p><p>#{'The public consultations held in April, with their dates and documents. ' * 3}</p>"
      html = "<title>Reporte abril 2023</title><body><article>#{body}</article></body>"

      Nokodown.to_markdown(html, url: "https://sb.gob.do/transparencia/consultas/reporte-abril-2023/")
              .should start_with("# Reporte abril 2023\n\n## Transparencia\n\nThe public")
    end

    it "drops a line below the title that only repeats it" do
      body = "<p><b>Fucili d'assalto</b></p><p>#{'The assault rifles of GTA 5 differ in damage, range and fire rate. ' * 3}</p>"
      html = "<title>Fucili d'assalto</title><body><article>#{body}</article></body>"

      Nokodown.to_markdown(html).should start_with("# Fucili d'assalto\n\nThe assault rifles")
    end

    it "keeps a first line named like the title that runs on into the next" do
      poem = "<p>Ode to the sea</p><p>#{'that rolls over the stones of the harbour and back again to the deep. ' * 3}</p>"
      html = "<title>Ode to the sea</title><body><article>#{poem}</article></body>"

      Nokodown.to_markdown(html).should start_with("# Ode to the sea\n\nOde to the sea\n\nthat rolls")
    end

    it "keeps the site's name heading the content on its home page" do
      body = "<p>#{'Arcade game with a bouncing ball, cosmic levels and endless runs to beat. ' * 3}</p>"
      html = "<title>Chickenin Route - Arcade Game</title><body><article><h1>Chickenin Route</h1>#{body}</article></body>"

      Nokodown.to_markdown(html, url: "https://www.chickenin-route.top/it/").should start_with("# Chickenin Route\n\nArcade game")
    end

    it "does not head content that has its own heading with a title that only names the site" do
      body = "<h2>David Hellenius</h2><p>#{'Swedish presenter, comedian and actor, known for his television shows. ' * 3}</p>"
      html = "<title>Edisonline SK</title><body><article>#{body}</article></body>"

      Nokodown.to_markdown(html, url: "https://edisonline.sk/catalog/category/person").should start_with("## David Hellenius\n\nSwedish")
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
    let(:product) do
      "<h1>Hardcover notebook, 200 sheets</h1><ul><li>Code: 31579</li><li>Barcode: 7894494526435</li>" \
        "<li>Brand: Jandaia</li><li>Package: 4 units</li><li>Weight: 0.4 kg</li></ul>" \
        "<p>A ruled notebook with a hard PET cover, a ribbon marker and a pocket inside the back cover. " \
        "The sheets are 56 g paper with a margin line, and the notebook is sold by the package.</p>"
    end
    let(:delivery) { "<div><h3>Delivery</h3><p>Orders leave our warehouse the next working day.</p></div>" }

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

    it "keeps the linked title of every post on a listing" do
      titles = ["Spring planting for small gardens", "Pruning roses without losing blooms", "Composting in a city kitchen"]
      posts = titles.each_with_index.map do |title, index|
        "<div class='post-item'><div class='post-header'><h2><a href='/posts/#{index}'>#{title}</a></h2>" \
          "<div class='post-date'>12 May 2026</div></div>" \
          "<p>#{'Our gardeners explain the method step by step, with photos of each stage and the tools they use. ' * 2}</p></div>"
      end

      markdown = extract("<main><h1>Blog</h1><div class='posts'>#{posts.join}</div></main>")

      titles.each_with_index { |title, index| markdown.should include("## [#{title}](https://example.com/posts/#{index})") }
    end

    it "still cleans what sits around a listing's posts" do
      posts = Array.new(3) do |index|
        "<div class='post-item'><h2><a href='/posts/#{index}'>Post #{index}</a></h2>" \
          "<p>#{'Our gardeners explain the method step by step, with photos of each stage and the tools they use. ' * 2}</p></div>"
      end
      promo = "<div class='promo-box'><p>Join the club for weekly tips</p><a href='/join'>Join</a></div>"

      extract("<main><h1>Blog</h1><div class='posts'>#{posts.join}</div>#{promo}</main>").should_not include("weekly tips")
    end

    it "drops a menu that links to the page itself, even on an index page" do
      topics = %w[
        Anatomy Astronomy Architecture Art Biology Botany Banking Baking Chemistry Climate Cooking Crafts
        Dentistry Design Drama Diving Ecology Economics Energy Ethics Farming Fashion Fishing Forestry
        Gardening Geography Geology Glassmaking Hiking History Horses Hunting
      ]
      index = "<ul>#{topics.map { |topic| "<li><a href=\"/topics/#{topic.downcase}\">#{topic}</a></li>" }.join}</ul>"
      menu = '<ul><li><a href="/news">News</a></li><li><a href="https://www.example.com/page/">Topics</a> (8)</li>' \
             '<li><a href="/events">Events</a></li></ul>'

      markdown = extract("<main><h1>Topics</h1>#{index}#{menu}</main>")

      markdown.should include("- [Baking](https://example.com/topics/baking)")
      ["News", "Events"].each { |noise| markdown.should_not include(noise) }
    end

    it "keeps the link lists above a title that opens nothing, like an SEO line at the foot of an index" do
      topics = %w[
        Anatomy Astronomy Architecture Art Biology Botany Banking Baking Chemistry Climate Cooking Crafts
        Dentistry Design Drama Diving Ecology Economics Energy Ethics Farming Fashion Fishing Forestry
        Gardening Geography Geology Glassmaking Hiking History Horses Hunting
      ]
      index = "<ul>#{topics.map { |topic| "<li><a href=\"/topics/#{topic.downcase}\">#{topic}</a></li>" }.join}</ul>"
      intro = "<p>Every subject the library holds, from anatomy to hunting. Each topic lists its books, the shelf " \
              "they stand on and when they are due back, and the librarians add new topics every month.</p>"

      markdown = extract("<main>#{intro}#{index}<h1>Topics for every reader</h1><p>Browse them all.</p></main>")

      markdown.should include("- [Anatomy](https://example.com/topics/anatomy)")
    end

    it "keeps the menu of an index page that holds little else" do
      topics = %w[Anatomy Astronomy Architecture Art Biology Botany Banking Baking Chemistry Climate Cooking Crafts]
      index = "<ul>#{topics.map { |topic| "<li><a href=\"/topics/#{topic.downcase}\">#{topic}</a></li>" }.join}</ul>"
      menu = '<ul><li><a href="/news">News</a></li><li><a href="/page">Topics</a></li>' \
             '<li><a href="/events">Events</a></li></ul>'

      markdown = extract("<main><h1>Topics</h1>#{index}#{menu}</main>")

      markdown.should include("- [Events](https://example.com/events)")
    end

    it "keeps a list of CJK headlines above the title of a page they dominate" do
      headlines = Array.new(20) { |index| "<li><a href=\"/news/#{index}\">东京大学研究团队发现新型超导材料样品 #{index + 1}</a></li>" }
      markdown = extract("<body><div><ul>#{headlines.join}</ul></div><div>#{product}</div></body>")

      markdown.should include("东京大学研究团队发现新型超导材料样品 20")
    end

    it "drops the menus above the page title even when they hold most of the text" do
      departments = %w[
        Party Toys Bedding Cleaning Office School Kitchen Garden Tools Paint Pets Books Music Sports Baby Lighting
        Bath Storage Crafts Travel
      ]
      groups = departments.map do |name|
        slug = "/#{name.downcase}"
        "<li><a href=\"#{slug}\">#{name}</a><ul><li><a href=\"#{slug}/new\">New</a></li>" \
          "<li><a href=\"#{slug}/sale\">Sale</a></li><li><a href=\"#{slug}/all\">All #{name}</a></li></ul></li>"
      end
      markdown = extract("<body><div><ul>#{groups.join}</ul></div><div>#{product}</div></body>")

      markdown.should include("- Barcode: 7894494526435")
      ["Party", "Bedding", "All Books"].each { |noise| markdown.should_not include(noise) }
    end

    it "drops a column of links beside the column of prose in a layout table" do
      news = ["Pool season opens with a new water system", "We are hiring installers for the summer",
              "How we rebuilt the city pool in three weeks", "A sauna for every home: our new range"]
      rail = news.map { |headline| "<p><a href=\"/news/#{headline.length}\">#{headline}</a></p>" }.join
      product = "<h2>Whirlpool bath M-2056A</h2><p>Made in China by Monalisa, 1860 x 830 x 730 mm, " \
                "with six jets, a heater and a headrest.</p><p>The acrylic shell is reinforced with fibreglass, " \
                "and the pump and the heater sit behind a panel that lifts off for service.</p>"

      markdown = extract("<table><tr><td>#{product}</td><td>#{rail}</td></tr></table>")

      markdown.should include("with six jets, a heater and a headrest.")
      markdown.should_not include("We are hiring")
    end

    it "keeps the index in a layout table column beside an intro" do
      topics = %w[
        Anatomy Astronomy Architecture Biology Botany Banking Chemistry Climate Cooking Dentistry
        Design Drama Ecology Economics Farming Fashion Geology History Hiking
      ]
      index = topics.map { |topic| "<a href=\"/topics/#{topic.downcase}\">#{topic}</a><br>" }.join
      intro = "<p>Welcome to the topic directory of our small library. Pick a subject to see the books we hold " \
              "on it and when they are due back.</p>"

      markdown = extract("<table><tr><td>#{intro}</td><td>#{index}</td></tr></table>")

      markdown.should include("[Geology](https://example.com/topics/geology)")
    end

    it "keeps a column of links that holds the page title" do
      names = %w[VMC750 VMC850 VMC1000 XH714 XH716]
      related = names.map { |name| "<a href=\"/p/#{name}\">#{name} vertical machining centre</a><br>" }.join
      product = "<h1>XHD2312 gantry machining centre</h1><img src=\"/img/xhd2312.jpg\">#{related}"
      contact = "<p>Sales: Zhai Qing, 138 9766 3235, or write to sales@qyskjc.com. Address: 24 Jing'er Road North, " \
                "Biological Park, Xining, Qinghai. Open from eight to five on working days, and on Saturday " \
                "mornings by appointment.</p>"

      markdown = extract("<table><tr><td>#{contact}</td><td>#{product}</td></tr></table>")

      markdown.should include("# XHD2312 gantry machining centre")
    end

    it "keeps cards whose tags link to the page itself" do
      tags = '<div><a href="/tags/tide">tide</a> <a href="/page">energy</a> <a href="/tags/coast">coast</a></div>'
      card = "<article><h2><a href=\"/notes/lagoon\">The lagoon wall opens</a></h2>#{tags}</article>"

      markdown = extract("<main><h1>Energy</h1>#{card}<p>Two more notes this week.</p></main>")

      markdown.should include("## [The lagoon wall opens](https://example.com/notes/lagoon)")
    end

    it "drops the heading over a box of links it drops" do
      kinds = %w[Notebooks Pens Folders Markers Erasers Rulers]
      links = kinds.map { |kind| "<li><a href=\"/shop/#{kind.downcase}\">#{kind}</a></li>" }.join
      box = "<div><h2>More from the shop</h2><ul>#{links}</ul></div>"

      markdown = extract("<main>#{product}#{box}#{delivery}</main>")

      markdown.should include("the notebook is sold by the package.\n\n### Delivery")
      markdown.should_not include("More from the shop")
    end

    it "keeps a title too long to be the label of the box of links below it" do
      tags = %w[Health Tech Equity].map { |tag| "<a href=\"/tags/#{tag.downcase}\">#{tag}</a>" }.join(" ")
      tags = "<div>#{tags}</div>"
      card = "<article><h2>The future of healthcare is digital: seven reasons why</h2>#{tags}</article>"

      markdown = extract("<main><h1>Piotr's posts</h1>#{card}<p>One more post this week.</p></main>")

      markdown.should include("## The future of healthcare is digital: seven reasons why")
      markdown.should_not include("Equity")
    end

    it "drops the heading over a box of links that a rule parts from the next section" do
      skills = %w[PHP Java Ruby Python Swift Kotlin]
      links = skills.map { |skill| "<li><a href=\"/jobs/#{skill.downcase}\">#{skill}</a></li>" }.join
      boxes = "<div><h2>Find jobs by type</h2><ul>#{links}</ul><hr><h3>Find jobs by skill</h3><ul>#{links}</ul></div>"

      markdown = extract("<main>#{product}#{boxes}#{delivery}</main>")

      markdown.should include("### Delivery")
      markdown.should_not include("by type")
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

      markdown.should include("- [Stoneware mug](https://example.com/p/mug)\n  $18")
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

    it "drops the messages Webflow shows only once a form is sent" do
      form = '<div class="w-form"><form><input name="email"></form><div class="w-form-done"><div>Thank you! Check your inbox.</div></div>' \
             '<div class="w-form-fail"><div>There was an issue with the form.</div></div></div>'

      convert("<p>Open daily.</p>#{form}").should == "Open daily."
    end

    it "drops link spam placed far off screen or in a strip one pixel high" do
      html = '<p>Open daily.</p><div style="position: absolute; left: -7786px;"><a href="https://spam.example">casino bonus</a></div>' \
             '<div style="position:fixed;top:-9000px"><a href="https://spam.example">live casino</a></div>' \
             '<div style="position:absolute;left:-999em"><a href="https://spam.example">slots</a></div>' \
             '<div style="overflow:hidden;height:1px;"><a href="https://spam.example">no kyc casino</a></div>'

      convert(html).should == "Open daily."
    end

    it "keeps screen-reader text clipped to one pixel in place, which can be the only copy of a price" do
      html = '<p>Camp kettle</p><span style="position:absolute;width:1px;height:1px;margin:-1px;overflow:hidden">Price: 30 euro</span>'

      convert(html).should == "Camp kettle\n\nPrice: 30 euro"
    end

    it "drops a large hidden block beside the visible title, but not an anti-flicker wrapper around the page" do
      article = "<h1>Trail stoves</h1><p>#{'A trail stove boils a litre in three minutes. ' * 14}</p>"
      copy = "<pre hidden>#{'# Trail stoves raw markdown copy of the article. ' * 8}</pre>"

      convert(article + copy).should_not include("raw markdown copy")
      convert("<div style='visibility:hidden'>#{article}</div>").should include("boils a litre")
    end
  end

  describe "title: false" do
    it "does not prepend the metadata title" do
      paragraph = "<p>Tidal lagoons hold water behind a wall at high tide, then release it through turbines.</p>"
      markdown = Nokodown.to_markdown("<title>Tides</title><body><article>#{paragraph * 4}</article></body>", title: false)

      markdown.should start_with("Tidal lagoons hold water")
    end

    it "keeps the article's own headline" do
      Nokodown.to_markdown(fixture("article.html"), title: false).should start_with("# How Tidal Power Plants Store Energy\n\nTidal lagoons")
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

    it "decides whether to keep it before it protects a listing's items" do
      papers = ["Lagoon walls under storm surge", "Sediment behind barrages", "Fish passage through turbines", "Grid timing of output",
                "Costs of the La Rance overhaul", "Pumping at high tide", "Bird life on lagoon walls", "Tidal range and siting"]
      items = papers.each_with_index.map do |title, index|
        "<div class='entry'><h3><a href='/papers/#{index}'>#{title}</a></h3><p>#{'A study of the wall and the water behind it. ' * 3}</p>" \
          "<div class='meta'><a href='/authors/a#{index}'>Ana Lima</a>, <a href='/authors/b#{index}'>Rui Costa</a></div></div>"
      end
      protected_runs = []
      Nokodown::Pruner.stub(:new).and_wrap_original do |original, nodes, mode, **options|
        protected_runs << !options[:keep].to_a.empty? if mode == :article && options.fetch(:conditional, true)
        original.call(nodes, mode, **options)
      end

      story("<h2>Papers</h2><div class='list'>#{items.join}</div>")

      protected_runs.should == [false, true]
    end

    it "keeps a heading whose anchor holds a negative class word" do
      markdown = story('<h2 id="h-media-coverage-of-tidal-lagoons">Media coverage of tidal lagoons</h2><p>Newspapers mostly covered the cost.</p>')

      markdown.should include("## Media coverage of tidal lagoons")
    end

    it "still drops comments whose heading carries a permalink" do
      markdown = story('<section id="comments"><h2>Comments<a href="#comments">¶</a></h2><p>Jane wrote: the turbine part was the clearest.</p></section>')

      markdown.should_not include("Comments")
      markdown.should_not include("Jane wrote")
    end

    it "keeps the wide-screen copy of a block laid out twice, but not a block shown only on wide screens" do
      pair = '<div><div class="hidden sm:block"><p>Wide screen copy of the steps.</p></div><div class="md:hidden"><p>Narrow screen copy of the steps.</p></div></div>'
      markdown = story("#{pair}<div class='hidden lg:block'><p>A rail of brand stories.</p></div>")

      markdown.should include("modest maintenance costs.")
      markdown.should include("Wide screen copy of the steps.")
      markdown.should_not include("Narrow screen copy")
      markdown.should_not include("brand stories")
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

    it "keeps the key facts between the headline and the body, and nothing after the body" do
      facts = { "Price" => "525,000 €", "Rooms" => "2", "Floor area" => "72 m²" }.map do |label, value|
        "<div class='fact'><div>#{label}</div><div>#{value}</div></div>"
      end
      prose = "<p>The flat sits on a quiet street of the Eixample, with tall windows, original tiles and a balcony.</p>" * 4
      html = "<main><div class='listing'><div class='crumbs-text'>Homes for sale</div>" \
             "<div class='intro'><h1>Flat for sale in the Eixample</h1><div class='facts'>#{facts.join}</div></div>" \
             "<div class='description'>#{prose}</div><div class='agent'><p>Call Ana on weekdays.</p></div></div></main>"

      markdown = Nokodown.to_markdown(html)
      markdown.should start_with("# Flat for sale in the Eixample\n\nPrice\n\n525,000 €")
      markdown.should include("original tiles")
      markdown.should_not include("Call Ana")
    end

    context "with an H1 above the body that does not name the page" do
      let(:prose) { "<p>The tour opened in Ohio with a set of songs the band had not played in thirty years, to a full hall.</p>" * 4 }

      def blog(title, logo)
        "<title>#{title}</title><body><div class='header-outer'><div class='titlewrapper'><h1 class='title'>#{logo}</h1></div>" \
          "<div class='descriptionwrapper'><p class='description'>Thoughts from a small allotment in the north.</p></div></div>" \
          "<div class='main-outer'><div class='date-outer'><h2 class='date-header'>Wednesday, April 25, 2026</h2>" \
          "<div class='post hentry'><h3 class='post-title'>Pruning roses in spring</h3><div class='post-body entry-content'>#{prose}</div>" \
          "<div class='post-footer'>Posted by Ann at 10:02</div></div></div></div></body>"
      end

      it "leaves out a blog's name linked to its home page" do
        html = blog("Garden Notes", "<a href='https://garden.example.com/'>Garden Notes</a>")

        Nokodown.to_markdown(html, url: "https://garden.example.com/2026/04/roses.html").should start_with("# Garden Notes\n\nThe tour opened")
      end

      it "leaves out a section label when a heading below names the post better" do
        Nokodown.to_markdown(blog("Pruning roses in spring", "Roses")).should start_with("# Pruning roses in spring\n\nThe tour opened")
      end

      it "leaves out a journal's name above a paper titled in the metadata" do
        html = "<title>Effects of propolis mouthwash on Candida albicans</title><body><main><div class='issue-wrap'>" \
               "<div class='journal-info'><h1>Journal of Advanced Biomedical Sciences</h1><div class='issue'>Volume 11, Issue 4</div></div>" \
               "<div class='abstract'>#{prose}</div><div class='cite'><p>Cite as JABS 11(4).</p></div></div></main></body>"

        Nokodown.to_markdown(html).should start_with("# Effects of propolis mouthwash on Candida albicans\n\nThe tour opened")
      end
    end

    it "keeps a body that sits in a list below the headline" do
      abstract = "<p>Digital puppetry is a form of computer animation in which performers control a model in real time.</p>" * 3
      html = "<title>Evolving performance control systems</title><body><h1>Evolving performance control systems</h1>" \
             "<p>Created by <a href='/langdon'>W. Langdon</a></p><dl><dt>@PhdThesis{Gildfind:thesis,</dt>" \
             "<ul><li>author = \"Andrew Gildfind\",</li><li>abstract = \"#{abstract}\"</li></ul></dl></body>"

      Nokodown.to_markdown(html).should include("Digital puppetry is a form")
    end

    it "leaves out bare text after the body when it reaches up to the headline" do
      prose = "<p>The flat sits on a quiet street of the Eixample, with tall windows, original tiles and a balcony.</p>" * 4
      html = "<main><div class='listing'><div class='intro'><h1>Flat for sale in the Eixample</h1><div class='price'>525,000 €</div></div>" \
             "<div class='description'>#{prose}</div>Posted by Ana | 3 comments</div></main>"

      Nokodown.to_markdown(html).should_not include("Posted by Ana")
    end

    it "does not reach up to a headline over a long stretch of other content" do
      features = Array.new(20) { |index| "<li>Feature #{index + 1} of this flat: a quiet detail of the place</li>" }
      prose = "<p>The flat sits on a quiet street of the Eixample, with tall windows, original tiles and a balcony.</p>" * 30
      html = "<main><div class='listing'><div class='intro'><h1>Flat for sale</h1><ul>#{features.join}</ul></div>" \
             "<div class='description'>#{prose}</div><div class='agent'><p>Call Ana on weekdays.</p></div></div></main>"

      Nokodown.to_markdown(html).should_not include("Feature 1 of this flat")
    end

    it "leaves out lines of links between the headline and the body, but not a linked date" do
      prose = "<p>The flat sits on a quiet street of the Eixample, with tall windows, original tiles and a balcony.</p>" * 4
      head = "<h1>Flat for sale in the Eixample</h1><div class='cats'><a href='/homes'>Homes</a> <a href='/barcelona'>Barcelona</a></div>" \
             "<div class='price'>525,000 €, two rooms, 72 m² of floor area</div><div class='date'><a href='/flat'>3 May 2026</a></div><div class='cta'><a href='/demo'>Book a visit</a></div>"
      html = "<main><div class='listing'><div class='intro'>#{head}</div><div class='description'>#{prose}</div></div></main>"

      markdown = Nokodown.to_markdown(html)
      markdown.should include("525,000 €")
      markdown.should include("3 May 2026")
      %w[Homes Barcelona Book].each { |label| markdown.should_not include(label) }
    end

    it "keeps the whole table of results when one row outscores the others" do
      authors = Array.new(60) { |index| "Moretti#{index}, A." }.join("; ")
      rows = [["Predicting kidney failure", authors], ["Preeclampsia before a biopsy", "Cabiddu, G."], ["Dialysis in older patients", "Rossi, M."]]
      body = rows.map { |title, names| "<tr><td>#{title}</td><td>2022</td><td>#{names}</td></tr>" }.join
      html = "<main><h1>Browse by journal</h1><table><thead><tr><th>Title</th><th>Date</th><th>Authors</th></tr></thead>" \
             "<tbody>#{body}</tbody></table></main>"

      markdown = Nokodown.to_markdown(html, title: false)
      markdown.should include("| Title | Date | Authors |")
      markdown.should include("| Preeclampsia before a biopsy | 2022 | Cabiddu, G. |")
    end
  end

  describe "protected email addresses" do
    it "decodes the addresses Cloudflare hides" do
      link = '<a href="/cdn-cgi/l/email-protection#f79494b7989492969984969192838e8385969e999e9990d994989a">' \
             '<span class="__cf_email__" data-cfemail="36555576595553575845575053424f4244575f585f58511855595b">[email&#160;protected]</span></a>'
      html = "<p>Questions about your certificate? Write to #{link} and we will answer within a day.</p>"

      markdown = Nokodown.to_markdown(html, url: "https://www.oceansafetytraining.com/cert", title: false)
      markdown.should include("cc@oceansafetytraining.com and")
      markdown.should_not include("protected")
    end

    it "writes a protected mail link that holds only the placeholder as its address" do
      html = '<p>Write to <a href="/cdn-cgi/l/email-protection#5a33343c351a3f223b372a363f74393537">[email&#160;protected]</a> today.</p>'

      Nokodown.to_markdown(html, title: false).should == "Write to info@example.com today."
    end

    it "drops a decoy that a stylesheet hides inside an address" do
      html = '<p>Email: <span class="obfuscate">info@ <span class="decoy-domain">ex.com</span> example.com</span></p>'

      Nokodown.to_markdown(html, title: false).should == "Email: info@example.com"
    end
  end

  describe "leaked markup" do
    def convert(body)
      Nokodown.to_markdown("<body>#{body}</body>", url: "https://example.com/page", title: false)
    end

    it "reads alt text that holds escaped markup as text" do
      convert('<p><img src="/pinot.jpg" alt="2020 Pinot Noir &lt;br&gt; Presqu’ile Vineyard"></p>')
        .should == "![2020 Pinot Noir Presqu’ile Vineyard](https://example.com/pinot.jpg)"
    end

    it "drops escaped elements written out whole, but not a tutorial's lines of markup" do
      convert("<p>&lt;abbr id=\"kygai\"&gt;&lt;/abbr&gt;</p><p>Garden furniture for every terrace.</p>").should == "Garden furniture for every terrace."
      convert("<p>Start the form with</p><p>&lt;form method=\"GET\" action=\"get.asp\"&gt;</p>")
        .should == "Start the form with\n\n\\<form method=\"GET\" action=\"get.asp\">"
    end

    it "drops PHP errors printed into the page" do
      error = "<br />\n<b>Warning</b>:  Use of undefined constant mimes in <b>/home/site/functions.php</b> on line <b>28</b><br />"

      convert("#{error}<p>Mestin recipes for camping.</p>").should == "Mestin recipes for camping."
    end

    it "drops Liquid errors" do
      html = "<p>Coffee <span>Liquid error (snippets/facets line 538): Could not find asset snippets/icon-close.liquid</span></p>"

      convert(html).should == "Coffee"
    end

    it "keeps the template's text after a Liquid error's message" do
      html = "<p>Type Liquid error (snippets/facets line 602): Could not find asset snippets/icon-arrow.liquid Coffee</p>" \
             "<p>Saved Liquid error (product-template line 135): divided by 0. Free shipping on every order.</p>"

      convert(html).should == "Type Coffee\n\nSaved Free shipping on every order."
    end

    it "leaves template placeholders and addresses in code alone" do
      html = "<p>Print <code>{{item.guest_name}}</code> in the template.</p><p>Run <code>info@ <span>ex.com</span> example.com</code></p>"

      convert(html).should == "Print `{{item.guest_name}}` in the template.\n\nRun `info@ ex.com example.com`"
    end

    it "looks for decoys in addresses in time linear in the lines of a page" do
      lines = Array.new(6000) { |index| "Week #{index}: Lakers @ Celtics, user#{index}@ example.org<br>" }
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      markdown = convert("<div>#{lines.join}</div>")

      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).should < 5
      markdown.should include("Week 5999: Lakers @ Celtics, user5999@ example.org")
    end

    it "drops template placeholders and shortcodes left unrendered" do
      body = "<p>{{item.guest_name}}, {{item.nationality}}</p><p>[mailerlite_form form_id=2]</p><p>{title}</p>" \
             "<p>Rooms with a view of the lake. {Christmas}</p>"

      convert(body).should == "Rooms with a view of the lake. {Christmas}"
    end

    it "drops counters a script never filled in" do
      convert("<p>The stove boils a litre in three minutes.</p><div class='like-icon'><a href=''>{{options.likeCount}}</a> " \
              "<span>{{ options.likeCount }}</span></div>").should == "The stove boils a litre in three minutes."
    end

    it "keeps template syntax in a code block" do
      block = "<div class='language-liquid highlighter-rouge'><div class='highlight'><pre><code>{{ page.title }}</code></pre></div></div>"

      convert("#{block}<p><code>{{ site.url }}</code></p>").should == "```liquid\n{{ page.title }}\n```\n\n`{{ site.url }}`"
    end

    it "keeps template placeholders written as code" do
      body = "<p>{{ page.title }}</p><p>Use <kbd>{{ page.title }}</kbd>, <samp>{{ site.url }}</samp> and " \
             "<tt>{{ content }}</tt> in the layout.</p>"

      convert(body).should == "Use `{{ page.title }}`, `{{ site.url }}` and `{{ content }}` in the layout."
    end
  end

  describe "deep nesting" do
    it "writes the text of elements and tables nested thousands deep" do
      [%w[<span> </span>], %w[<div> </div>], %w[<blockquote> </blockquote>], %w[<table><tr><td> </td></tr></table>]].each do |open, close|
        html = "<p>#{'An opening sentence long enough to be prose. ' * 4}</p>#{open * 3000}Deep text here#{close * 3000}"

        [true, false].each { |main| Nokodown.to_markdown(html, main_content: main, title: false).should include("Deep text here") }
      end
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

    it "reads a page declared Latin-1 as Windows-1252" do
      html = "<meta charset=iso-8859-1><p>\x93Caf\xE9\x94 \x96 open</p>".b

      Nokodown.to_markdown(html, title: false).should == "“Café” – open"
    end

    it "reads the charset of a <meta> deep in the head" do
      html = "<head><script>#{"x" * 5000}</script><meta charset=windows-1254></head><p>K\xFDble y\xF6n\xFC</p>".b

      Nokodown.to_markdown(html, title: false).should == "Kıble yönü"
    end

    it "reads the encoding of an XML declaration" do
      html = "<?xml version=\"1.0\" encoding=\"windows-1251\"?><html><body><p>\xCF\xF0\xE8\xE2\xE5\xF2</p></body></html>".b

      Nokodown.to_markdown(html, title: false).should == "Привет"
    end

    it "reads bytes that are UTF-8 as UTF-8 whatever the page declares" do
      html = "<meta charset=windows-1251><p>Привет, мир</p>".b

      Nokodown.to_markdown(html, title: false).should == "Привет, мир"
    end

    it "detects the encoding of a page that declares none" do
      {
        "Windows-1252" => "Ein schöner Tag für große Äpfel und süße Öle",
        "Windows-1251" => "Добро пожаловать на наш форум о рыбалке",
        "KOI8-R" => "Добро пожаловать на наш форум о рыбалке",
        "Shift_JIS" => "今日はとても良い天気ですね。散歩に行きましょう。",
        "GBK" => "欢迎来到我们的网站，这里有最新的产品信息。",
        "EUC-KR" => "우리 웹사이트에 오신 것을 환영합니다. 최신 소식을 확인하세요.",
        "Big5" => "歡迎來到我們的網站，這裡有最新的產品資訊。",
        "EUC-JP" => "今日はとても良い天気ですね。散歩に行きましょう。"
      }.each do |encoding, text|
        Nokodown.to_markdown("<p>#{text}</p>".encode(encoding).b, title: false).should == text
      end
    end

    it "reads UTF-16 by its byte order mark" do
      %w[UTF-16LE UTF-16BE].each do |encoding|
        Nokodown.to_markdown("\uFEFF<p>Grüße aus Köln</p>".encode(encoding).b, title: false).should == "Grüße aus Köln"
      end
    end

    it "reads accented pairs inside words as Western, not as Han" do
      html = "<p>Anota\xE7\xF5es e informa\xE7\xF5es da legisla\xE7\xE3o: administra\xE7\xE3o, cat\xE1logo, in\xEDcio, " \
             "respons\xE1vel, situa\xE7\xE3o, publica\xE7\xF5es, altera\xE7\xF5es, revoga\xE7\xE3o</p>".b

      Nokodown.to_markdown(html, title: false).should == "Anotações e informações da legislação: administração, catálogo, " \
                                                          "início, responsável, situação, publicações, alterações, revogação"
    end

    it "reads stray bytes in UTF-8 as Windows-1252" do
      html = "<meta charset=utf-8><p>Ünïcödé text, Reykjav\xEDk \xA9 2020</p>".b

      Nokodown.to_markdown(html, title: false).should == "Ünïcödé text, Reykjavík © 2020"
    end

    it "reads stray bytes in UTF-8 in the single-byte charset that the page declares" do
      html = "<meta charset=windows-1251><p>Привет, мир, \xB9 5</p>".b

      Nokodown.to_markdown(html, title: false).should == "Привет, мир, № 5"
    end

    it "reads a Western page's runs that are UTF-8 by chance as Windows-1252" do
      html = "<meta charset=iso-8859-1><p>\x84Ohne Unterla\xDF\x93, sagt K\xF6ln, caf\xE9\xA0\xBB \x96 und caf\xC3\xA9</p>".b

      Nokodown.to_markdown(html, title: false).should == "„Ohne Unterlaß“, sagt Köln, café » – und café"
    end

    it "drops what is left of a character cut off" do
      html = "<meta charset=utf-8><p>Zażółć gęślą jaźń przekaza\xC4...</p>".b

      Nokodown.to_markdown(html, title: false).should == "Zażółć gęślą jaźń przekaza..."
    end

    it "undoes UTF-8 read as Windows-1252" do
      html = "<p>CafÃ© crÃ¨me, itâ€™s ÐŸÑ€Ð¸Ð²ÐµÑ‚ Ã¢â‚¬â€œ twice</p>".b

      Nokodown.to_markdown(html, title: false).should == "Café crème, it’s Привет – twice"
    end

    it "drops a misread run that reads back as control characters only" do
      Nokodown.to_markdown("<p>Fall 2017</p><p>ÂŽ</p>".b, title: false).should == "Fall 2017"
    end

    it "keeps letters that only look like UTF-8 read as Windows-1252" do
      html = "<p>Spaß\u00A0an der « identité\u00A0» und 2×–3×</p>".b

      Nokodown.to_markdown(html, title: false).should == "Spaß an der « identité » und 2×–3×"
    end

    it "reads valid UTF-8 quickly when its letters come before signs" do
      text = "phí” lệ, áš " * 200_000
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      html = Nokodown::Charset.utf8("<p>#{text}</p>".b)

      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).should < 1
      html.should == "<p>#{text}</p>"
    end

    it "returns nothing for a PDF, an image or an archive served as a page" do
      ["%PDF-1.6\r%\xE2\xE3\xCF\xD3\r\n1 0 obj <</Type /Catalog>> endobj", "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR",
       "PK\x03\x04\x14\x00\x00\x00<html><p>Inside</p>"].each do |body|
        result = Nokodown.extract(body.b)

        result.markdown.should == ""
        result.mode.should == :none
      end
    end

    it "returns nothing for a body made mostly of control bytes" do
      body = "<html><body><p>Download</p>#{"\x01\x9C\x00\x12\xF3\x07ab" * 200}</body></html>".b

      Nokodown.extract(body).markdown.should == ""
    end

    it "does not take UTF-16 without a byte order mark for binary" do
      Nokodown::Charset.binary?("<html><body><p>Grüße aus Köln</p></body></html>".encode("UTF-16LE").b).should be false
    end

    it "drops byte order marks and replacement characters" do
      Nokodown.to_markdown("\uFEFF<p>a\uFEFFb\uFFFDc</p>".b, title: false).should == "abc"
    end
  end
end

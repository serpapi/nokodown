# frozen_string_literal: true

RSpec.describe Nokodown::Boilerplate do
  def cleaned(html, url: nil)
    body = Nokolexbor::HTML("<html><body>#{html}</body></html>").at_css("body")
    Nokodown::Preprocessor.new(body).call
    Nokodown::Boilerplate.new(body, url: url).call
    body
  end

  # Text left by boilerplate removal alone, before the content is located.
  def remaining(html, url: nil)
    Nokodown::Dom.text(cleaned(html, url: url))
  end

  def prose(topic, count)
    sentence = "#{topic} is explained here in a sentence long enough to read like a real paragraph of an article. "
    Array.new(count) { |index| "<p>#{sentence * 2}Part #{index + 1}.</p>" }.join
  end

  describe "ad class names" do
    it "does not read ad into generated hashes" do
      html = <<~HTML
        <div class="elementor-element elementor-element-2638ad0">Heat pumps move heat instead of making it.</div>
        <div class="jXK9ad">They keep working at minus twenty degrees.</div>
        <div class="w-node-b5343ad4-1c2e-ad12-9f0b-3c4d5e6f7a8b">Most homes need a 7 kW unit.</div>
      HTML

      text = remaining(html)
      text.should include("move heat")
      text.should include("minus twenty")
      text.should include("7 kW unit")
    end

    it "does not read ad into CSS module hashes" do
      remaining('<table class="mdx-table_root__adKqa"><tr><td>Provisioner type</td></tr></table>').should == "Provisioner type"
    end

    it "removes ad slots, including sized ones" do
      html = <<~HTML
        <p>Heat pumps move heat instead of making it.</p>
        <div class="ad">Boiler sale</div><div class="ad-slot">Radiator deals</div><div id="ads">Insulation offers</div>
        <div class="ad300x250">Solar quotes</div><div class="top-gpt-ad">Window grants</div>
      HTML

      remaining(html).should == "Heat pumps move heat instead of making it."
    end
  end

  describe "Tailwind class names" do
    it "does not read names into arbitrary values, but still reads the utility name" do
      html = <<~HTML
        <p>Heat pumps move heat instead of making it.</p>
        <div class="lg:h-[calc(100vh-var(--nav-height))]">They keep working at minus twenty degrees.</div>
        <div class="data-[state=open]:sidebar-shown">Find an installer near you.</div>
      HTML

      remaining(html).should == "Heat pumps move heat instead of making it. They keep working at minus twenty degrees."
    end
  end

  describe "sections named like furniture" do
    let(:article) { "<h1>Choosing a heat pump</h1>#{prose('Sizing', 6)}" }

    it "keeps prose sections named after their table of contents entry or skip link" do
      html = <<~HTML
        #{article}
        <section id="toc_123" class="toc-para"><h2>Running costs</h2>#{prose('Running cost', 3)}</section>
        <div id="topic2" class="skip-item"><h2>Noise</h2>#{prose('Noise', 3)}</div>
        <div class="accordion_drawer"><h2>Grants</h2>#{prose('Grants', 3)}</div>
      HTML

      text = remaining(html)
      text.should include("Running cost is explained")
      text.should include("Noise is explained")
      text.should include("Grants is explained")
    end

    it "keeps the heading of a prose section named like a drawer" do
      html = <<~HTML
        #{article}
        <div class="mntl-sc-block-accordion_drawer"><h2 class="mntl-sc-block-accordion_drawer__heading">Paying for it</h2>#{prose('Grants', 3)}</div>
      HTML

      remaining(html).should include("Paying for it")
    end

    it "still removes a table of contents, and prose in a sidebar or a newsletter drawer" do
      html = <<~HTML
        #{article}
        <div class="toc"><a href="#costs">Running costs</a> <a href="#noise">Noise</a> <a href="#grants">Grants</a></div>
        <div class="sidebar">#{prose('Our company', 3)}</div>
        <div class="newsletter-drawer">#{prose('Our newsletter', 3)}</div>
      HTML

      text = remaining(html)
      text.should_not include("Running costs")
      text.should_not include("Our company")
      text.should_not include("Our newsletter")
    end
  end

  describe "modifier class names" do
    it "keeps wrappers named for what they have or allow, not for what they are" do
      html = <<~HTML
        <div class="content-container has-sidebar">#{prose('Grinding coffee', 1)}</div>
        <div class="clearfix with-navigation">#{prose('Brewing', 1)}</div>
        <div class="td-content-and-menu">#{prose('Storing beans', 1)}</div>
        <div class="o_wsale_container o_wsale_has_sidebar">#{prose('Roasting', 1)}</div>
        <div class="product-grid sidebar-enabled--true"><a href="/p/1">House blend</a> <a href="/p/2">Dark roast</a></div>
        <div class="sidebar"><p>Archive of older posts</p></div>
      HTML

      text = remaining(html)
      ["Grinding coffee", "Brewing", "Storing beans", "Roasting", "House blend"].each { |content| text.should include(content) }
      text.should_not include("Archive")
    end

    it "still reads no-print as a name" do
      remaining("#{prose('Grinding coffee', 3)}<div class='no-print'><a href='?print=1'>Print this page</a></div>").should_not include("Print this")
    end
  end

  describe "chrome elements around the content" do
    it "keeps a footer or reading pane that holds the page's only h1, not the site footer" do
      ["footer", "div role='complementary'"].each do |tag|
        html = <<~HTML
          <header class="site-header"><a href="/">Auto Lexicon</a></header>
          <#{tag} class="elementor-location-single"><h1>Lancia Musa</h1>#{prose('The Musa', 2)}</#{tag.split.first}>
          <footer class="site-footer"><p>Imprint and privacy of the publisher of this site, who answers mail weekly.</p></footer>
        HTML

        text = remaining(html)
        text.should include("Lancia MusaThe Musa is explained")
        text.should_not include("Imprint")
      end
    end

    it "removes a footer or side pane whose h1 is the site's name linked home" do
      ["footer", "aside"].each do |tag|
        html = "<#{tag}><h1><a href=\"/\">Auto Lexicon</a></h1><p>Car reviews since 1998, written in Turin.</p></#{tag}>" \
               "<h2>Lancia Musa</h2><p>A small car with a tall roof and room for five.</p>"

        remaining(html).should_not include("Auto Lexicon")
      end
    end
  end

  describe "noise names" do
    it "removes a related block even when its classes also name content" do
      html = "<article>#{prose('Sizing', 8)}</article><div class=\"related-posts entry-related\">#{prose('Another heat pump story', 2)}</div>"

      remaining(html).should_not include("Another heat pump story")
    end

    it "removes forum signatures, not the post" do
      html = <<~HTML
        <div class="message">
          <div class="message-userContent">#{prose('Bleeding the radiators', 2)}</div>
          <aside class="message-signature">My rig: a 7 kW air source pump and twelve radiators.</aside>
        </div>
      HTML

      text = remaining(html)
      text.should include("Bleeding the radiators is explained")
      text.should_not include("My rig")
    end

    it "keeps the largest guessed block when removing furniture would leave nothing" do
      products = Array.new(6) { |index| "<a href=\"/mower-#{index}\">Robotic mower KR#{index}00 for lawns up to #{index + 1} acres</a>" }
      html = "<header><a href='/'>Home</a></header><section class=\"related-product\">#{products.join}</section><footer>Contact us</footer>"

      remaining(html).should include("Robotic mower KR500")
    end

    it "keeps the largest guessed block when a cookie banner that outweighs it goes" do
      products = Array.new(6) { |index| "<a href=\"/mower-#{index}\">Robotic mower KR#{index}00 for lawns up to #{index + 1} acres</a>" }
      notice = "<p>Google Analytics counts the visits to this site and how long visitors stay on each page.</p>" * 6
      html = "<h1>Mowers</h1><section class=\"related-product\">#{products.join}</section>" \
             "<div class=\"cmplz-cookiebanner-container\"><div class=\"cmplz-cookiebanner\">#{notice}</div></div>"

      text = remaining(html)
      text.should include("Robotic mower KR500")
      text.should_not include("Google Analytics")
    end
  end

  describe "disclaimers" do
    it "removes fine print about the site and its offers" do
      html = <<~HTML
        <div class="disclaimer">We may earn money when you click on our links.</div>
        #{prose('Choosing a mover', 3)}
        <figure><img src="/truck.jpg" alt=""></figure>
        <div class="disclaimer"><div class="disclaimer__text"><p>*Offer valid for new bookings only.</p></div></div>
      HTML

      text = remaining(html)
      text.should include("Choosing a mover is explained")
      text.should_not include("earn money")
      text.should_not include("Offer valid")
    end

    it "keeps the footnote to a mark in the table right before it" do
      table = "<table><tr><th>Mover</th><th>Coverage</th></tr><tr><td>Atlas Vans</td><td>40-46 states*</td></tr></table>"
      note = "<div class=\"disclaimer\"><div class=\"disclaimer__text\"><p>*Atlas serves 40 states for pickup and 46 for delivery.</p></div></div>"

      remaining("#{prose('Choosing a mover', 3)}#{table}#{note}").should include("*Atlas serves 40 states")
    end

    it "keeps a note that continues the prose, but not one after a line of links" do
      html = <<~HTML
        #{prose('Choosing hemp gummies', 2)}
        <h2>Is it legal in your state?</h2>
        <p>Hemp gummies with less than 0.3% THC by dry weight are legal under federal law across the country.</p>
        <p class="gray-disclaimer">Note: state laws vary, so check yours before you buy.</p>
        <p><a href="/terms">Terms</a> <a href="/privacy">Privacy</a></p>
        <p class="gray-disclaimer">Statements here have not been evaluated by the FDA.</p>
      HTML

      text = remaining(html)
      text.should include("Note: state laws vary")
      text.should_not include("not been evaluated")
    end

    it "removes a footer disclaimer right after the prose" do
      %w[footer__disclaimer footer_disclaimer site-footer-disclaimer disclaimer-footer].each do |name|
        html = "#{prose('Choosing an index fund', 3)}<p class=\"#{name}\">All content on this website is for information only.</p>"

        remaining(html).should_not include("for information only")
      end
    end

    it "keeps a block whose modifier says it has a disclaimer" do
      html = "#{prose('Choosing a smart lock', 2)}<div class=\"chart hasDisclaimer\"><p>Smart locks open with a code, a phone or a key.</p></div>"

      remaining(html).should include("Smart locks open")
    end
  end

  describe "share links" do
    it "removes links that ask a network to share the page, whatever their label" do
      html = "#{prose('Bonsai care', 2)}<ul><li><a href=\"http://www.facebook.com/sharer.php?u=https%3A%2F%2Fex.com\">シェア</a></li>" \
             "<li><a href=\"https://www.linkedin.com/shareArticle?mini=true\">Partager sur LinkedIn</a></li>" \
             "<li><a href=\"mailto:?subject=Bonsai\">Envoyer</a></li></ul><p>Write to <a href=\"mailto:ana@ex.com\">Ana</a> " \
             "or <a href=\"https://api.whatsapp.com/send?phone=34600000000\">message us</a>.</p>"
      text = remaining(html)

      %w[シェア LinkedIn Envoyer].each { |label| text.should_not include(label) }
      text.should include("Write to Ana or message us")
    end
  end

  describe "breadcrumb trails" do
    it "removes a trail from the home page that no class names, in any language" do
      trails = [
        '<div><a href="https://shop.example/">首页</a> &gt; <a href="/dushi/">都市小说</a> &gt; 厌世假少爷</div>',
        '<ol><li><a href="/">Úvod</a></li><li><a href="/umeni">Umění</a></li><li>Afghanistán známky</li></ol>',
        '<span>Ti trovi in: <a href="index.php">Home</a> -&gt; <a href="ricerca.php">Ricerca</a> -&gt; Volume 0002</span>',
        '<div><a href="/">Главная</a> / Люше (LYS)</div>'
      ]
      trails.each do |trail|
        text = remaining("#{trail}#{prose('Choosing a stamp album', 2)}")

        text.should start_with("Choosing a stamp album")
      end
    end

    it "keeps a category link followed by the post's date" do
      remaining("<div><a href=\"/\">Home</a> | 20.07.2026 08:42</div>#{prose('Health', 2)}").should include("20.07.2026")
    end

    it "keeps a trail-shaped run of links that a sentence continues" do
      sentences = {
        "<p>Open <span><a href=\"/\">Home</a> › <a href=\"/account\">Account</a></span> and pick the order to send back.</p>" =>
          "Open Home › Account and pick",
        "<ul><li><a href=\"https://github.com/\">GitHub</a> / <a href=\"https://github.com/rails\">rails</a> is where Rails lives</li></ul>" =>
          "GitHub / rails is where"
      }
      sentences.each { |sentence, text| remaining("#{prose('Returns', 2)}#{sentence}").should include(text) }
    end

    it "keeps a numbered list of links" do
      steps = '<ol><li><a href="/">Homepage</a></li><li><a href="/settings">Settings</a></li><li><a href="/settings/close">Close account</a></li></ol>'

      remaining("#{prose('Closing an account', 2)}#{steps}").should include("Close account")
    end

    it "keeps a credit linking to another site's home page" do
      html = "<p>See <a href=\"https://museum.example/visit\">opening hours</a> and <a href=\"https://museum.example/shop\">the shop</a>.</p>" \
             "#{prose('The Roman theatre', 2)}<p>© Photo: <a href=\"http://www.archeotech.ch/\">Archéotech S.A.</a> / SACV</p>"

      remaining(html).should include("Archéotech S.A. / SACV")
    end

    it "keeps a list of other sites, each linked at its home page with a description" do
      html = "#{prose('Salary research', 2)}<ul><li><a href=\"https://www.salary.com/\">Salary.com</a> – salaries by industry and zip code</li>" \
             "<li><a href=\"https://www.homefair.com/\">HomeFair.com</a>: a relocation guide with a salary calculator</li></ul>"

      text = remaining(html)
      text.should include("salaries by industry")
      text.should include("relocation guide")
    end
  end

  describe "site headers" do
    it "removes a header above the page's title however much it holds" do
      notices = Array.new(12) { |index| "<li>Service centre #{index + 1}: 600 Friendship Road, open 8:30 to 18:30 by appointment</li>" }
      html = "<div class=\"header\"><ul>#{notices.join}</ul></div><h1>Repairing a chronograph</h1>#{prose('Servicing a watch', 1)}"

      remaining(html).should_not include("Service centre")
    end

    it "keeps a header that holds the page's prose above a banner's title" do
      html = "<div class=\"main\"><header><h2>Neurology</h2>#{prose('Nerve pain', 3)}</header></div>" \
             "<div class=\"banner\"><h1>New Medicine</h1></div>"

      remaining(html).should include("Nerve pain")
    end

    it "keeps a header that holds the title or follows it" do
      notices = Array.new(12) { |index| "<li>Branch #{index + 1}: 600 Friendship Road, open 8:30 to 18:30 by appointment</li>" }.join
      ["<div class=\"header\"><h1>Branches</h1><ul>#{notices}</ul></div>",
       "<h1>Branches</h1><div class=\"header\"><ul>#{notices}</ul></div>"].each do |html|
        remaining(html).should include("Branch 12")
      end
    end
  end

  describe "furniture that outweighs a short page" do
    def hours
      days = %w[Monday Tuesday Wednesday Thursday Friday Saturday].map { |day| "#{day} 9:00-13:00, 14:00-17:30" }
      "<p>Sakura Clinic<br>3-6-1 Kego, Fukuoka<br>Tel 092 725 7900<br>#{days.join('<br>')}</p>"
    end

    it "removes a sidebar or footer beside a short post" do
      ["<div id=\"sidebar\"><h2>Contact</h2>#{hours}</div>", "<div class=\"footer\"><h2>Contact</h2>#{hours}</div>"].each do |box|
        html = "<div class=\"main\"><h1>Fully booked on Friday</h1><p>The morning slots are taken.</p></div>#{box}"

        text = remaining(html)
        text.should include("The morning slots are taken.")
        text.should_not include("Sakura Clinic")
      end
    end

    it "keeps a block named like a sidebar under a title that stands alone" do
      html = "<div class=\"main\"><div class=\"title\"><h1>Sakura Clinic</h1></div><div id=\"sidebar\">#{hours}</div></div>"

      remaining(html).should include("Monday 9:00")
    end

    it "keeps a block laid out beside a sidebar" do
      products = Array.new(6) do |index|
        "<li><a href=\"/disc-#{index}\">Diamond disc #{index + 1}25 mm</a> Segmented rim for granite and concrete, #{index + 3}50 UAH</li>"
      end
      html = "<div class=\"main\"><h1>Diamond discs</h1><p>Cutting discs for stone.</p></div>" \
             "<ul class=\"catalog-grid catalog-grid--m catalog-grid--sidebar\">#{products.join}</ul>"

      remaining(html).should include("Segmented rim")
    end

    it "keeps a sidebar or footer that holds prose, in paragraphs or in other blocks" do
      descriptions = %w[Acupuncture Massage Cupping].map do |treatment|
        "<div class=\"service\"><h3>#{treatment}</h3><div class=\"description\">#{treatment} eases the pain in the back " \
          "and the neck, and helps the patient sleep through the night again.</div></div>"
      end
      ["<div id=\"sidebar\">#{prose('Our new address', 2)}</div>", "<div id=\"footer\">#{descriptions.join}</div>"]
        .each do |box|
        html = "<div class=\"main\"><h1>Clinic news</h1><p>We moved to Kego, two streets from the station.</p></div>#{box}"

        remaining(html).should match(/Part 2|helps the patient sleep/)
      end
    end

    it "removes a narrower grid column of links that outweighs the title's column" do
      posts = ["Taiwan Graduate Scholarships", "Stirling Vice Chancellor Scholarship", "Gordon University Scholarship"]
      cards = posts.map.with_index do |post, index|
        "<div class=\"module\"><a href=\"/category/#{index}/\">Fully Funded</a>" \
          "<h3><a href=\"/post-#{index}/\">#{post} 2027</a></h3></div>"
      end
      html = "<div class=\"row\"><div class=\"col-12 col-md-8\"><p>Home › Tags › Konstanz Fellowship</p>" \
             "<h1>Tag: Konstanz Fellowship</h1><p>No posts to display</p></div>" \
             "<div class=\"col-12 col-md-4\"><h4>Latest Articles</h4>#{cards.join}</div></div>"

      text = remaining(html)
      text.should include("No posts to display")
      text.should_not include("Latest Articles")
      text.should_not include("Gordon University")
    end

    it "keeps a wider grid column, and a narrower one beside a title's column with prose, more text or the title" do
      guides = Array.new(12) { |index| "<h3><a href=\"/guide-#{index}/\">Fellowship guide, part #{index + 1}</a></h3>" }
      side = "<div class=\"col-md-4\"><h4>Guides</h4>#{guides.join}</div>"
      trail = "<p>Home › Fellowships › Germany</p>"
      rows = ["<div class=\"col-md-8\">#{trail}<h1>Konstanz Fellowship</h1>#{prose('The fellowship', 1)}</div>#{side}",
              "<div class=\"col-md-8\"><h1>Sakura Clinic</h1>#{hours}</div><div class=\"col-md-4\">#{guides.last(3).join}</div>",
              "<div class=\"col-md-8\"><h1>Konstanz Fellowship</h1></div>#{side}",
              "<div class=\"col-md-4\">#{trail}<h1>Konstanz Fellowship</h1></div>#{side.sub('col-md-4', 'col-md-8')}"]
      rows.each do |row|
        remaining("<div class=\"row\">#{row}</div>").should include("part 12")
      end
    end

    it "keeps a narrower grid column of the page's own links, as a profile's publications" do
      papers = ["Tidal mixing in shallow harbors", "Sediment transport under ferry wakes", "A model of quay wall erosion",
                "Salt marsh recovery after dredging", "Measuring wave energy at breakwaters", "Harbor seiches in closed basins"]
      links = papers.map { |paper| "<li><a href=\"/papers/#{paper.downcase.tr(' ', '-')}\">#{paper}</a></li>" }
      html = "<div class=\"row\"><div class=\"col-md-8\"><p>Home › People › Ana Puig</p><h1>Dr. Ana Puig</h1>" \
             "<ul><li>Professor of coastal engineering</li><li>Room 3.14, Harbor Building</li></ul></div>" \
             "<div class=\"col-md-4\"><h4>Publications</h4><ul>#{links.join}</ul></div></div>"

      remaining(html).should include("Harbor seiches in closed basins")
    end

    it "keeps a listing that wraps below a full-width title column in its row" do
      posts = ["How ports plan for rising seas", "Inside a container terminal at night", "Why harbor pilots still matter"]
      articles = posts.map.with_index do |post, index|
        "<article><h2><a href=\"/2026/10/post-#{index}/\">#{post}</a></h2><div>Oct #{20 - index}, 2026</div></article>"
      end
      popular = Array.new(5) { |index| "<li><a href=\"/popular-#{index}/\">Popular post #{index + 1}</a></li>" }
      [%w[col-12 col-lg-8 col-lg-4], %w[col-md-12 col-md-8 col-md-4]].each do |head, listing, side|
        html = "<div class=\"row\"><div class=\"#{head}\"><h1>Category: Ports</h1><p>Stories about the harbor and " \
               "its ports.</p></div><div class=\"#{listing}\">#{articles.join}</div>" \
               "<div class=\"#{side}\"><h3>Popular</h3><ul>#{popular.join}</ul></div></div>"

        remaining(html).should include("Why harbor pilots still matter")
      end
    end

    it "removes a site header above the title that holds addresses in lines" do
      html = "<div class=\"site-header\">#{hours * 2}</div><h1>Fully booked on Friday</h1>" \
             "<p>#{'The morning slots are taken. ' * 8}</p>"

      remaining(html).should_not include("Sakura Clinic")
    end

    it "removes a cookie banner that holds most of a page's text, named for what it is or laid over the page" do
      notice = "<p>Google Analytics counts the visits to this site and how long visitors stay on each page.</p>" * 4
      banners = ["<div id=\"dlgcookies\">#{notice}</div>", "<div class=\"widget-cookie-banner\"><h2>Cookie Policy</h2>#{notice}</div>",
                 "<div class=\"cookies\" style=\"position: fixed; bottom: 0\">#{notice}</div>"]
      banners.each do |banner|
        remaining("<h1>Lake at dawn</h1><img src=\"/lake.jpg\">#{banner}").should_not include("Google Analytics")
      end
    end

    it "keeps a cookie policy, the body of a page about cookies and a form named for them" do
      notice = "<p>Google Analytics counts the visits to this site and how long visitors stay on each page.</p>" * 4
      policy = "<h1>Privacy</h1><div class=\"cookie-policy\"><h2>Cookies we use</h2>#{notice}<h2>Refusing them</h2>#{notice}</div>"
      page = "<h1>Cookies</h1><div class=\"cookies-banner\"><p>We use cookies.</p></div><section class=\"cookies-page__body\">#{notice}</section>"
      form = "<h1>Create an account</h1><div class=\"user-info-from-cookie\">#{notice}</div>"

      remaining(policy).should include("Refusing them")
      remaining(page, url: "https://wordsforlife.org.uk/cookies/").should include("Google Analytics")
      remaining(form).should include("Google Analytics")
    end

    it "keeps a product whose tags name cookies and a bar" do
      notice = "<p>Google Analytics counts the visits to this site and how long visitors stay on each page.</p>" * 4
      product = "<div class=\"product type-product product_tag-buy-girl-scout-cookies-online product_tag-bar-harbor\">#{notice}</div>"

      remaining("<h1>Super Silver Haze</h1>#{product}").should include("Google Analytics")
    end

    it "keeps a block named for consent alone" do
      notice = "<p>Google Analytics counts the visits to this site and how long visitors stay on each page.</p>" * 4

      remaining("<h1>Study</h1><div class=\"consent-text\">#{notice}</div>").should include("Google Analytics")
      remaining("<h1>Study</h1><div class=\"entry informed-consent\">#{notice}</div>").should include("Google Analytics")
    end

    it "keeps a block named as a cookie notice that holds the page's title" do
      notice = "<p>Google Analytics counts the visits to this site and how long visitors stay on each page.</p>" * 4

      remaining("<div class=\"cookie-notice-container page\"><h1>Lake at dawn</h1>#{notice}</div>").should include("Google Analytics")
    end
  end

  describe "member panels" do
    def post(panel)
      "<div class=\"message\">#{panel}<div class=\"message-userContent\">#{prose('Bleeding the radiators', 2)}</div></div>"
    end

    # The line the panel beside the post was reduced to.
    def line(panel)
      line = cleaned(post(panel)).at_css(".message > p")
      line && Nokodown::Dom.text(line)
    end

    it "reduces the panel beside a post to the poster's name" do
      panel = <<~HTML
        <div class="message-user">
          <div class="message-avatar"><a href="/members/ana.12/"><img src="/avatars/12.jpg" alt="Ana"></a></div>
          <h4 class="message-name"><a href="/members/ana.12/" class="username">Ana Ruiz</a></h4>
          <h5 class="userTitle">Well-known member</h5>
          <dl class="pairs"><dt>Joined</dt><dd>Jan 2020</dd><dt>Messages</dt><dd>120</dd></dl>
        </div>
      HTML

      line(panel).should == "Ana Ruiz"
      remaining(post(panel)).should_not include("member")
      remaining(post(panel)).should_not include("Joined")
    end

    it "takes the name from the profile link a panel opens with" do
      panel = '<dl class="postprofile"><dt><a href="/u/7"><img src="/a/7.png" alt="avatar"></a> <a href="/u/7">Ana</a></dt>' \
              "<dd>Senator</dd><dd><strong>Posts:</strong> 4032</dd></dl>"

      line(panel).should == "Ana"
      remaining(post(panel)).should_not include("Posts")
    end

    it "leaves no line when the post opens with a by-line naming the poster" do
      html = '<div class="post"><dl class="postprofile"><dt><a href="/u/7" class="username">Ana</a></dt><dd>Posts: 12</dd></dl>' \
             '<div class="postbody"><p class="author">by <strong><a href="/u/7">Ana</a></strong> » Mon Jan 8, 2024</p>' \
             "#{prose('Bleeding the radiators', 2)}</div></div>"

      remaining(html).scan("Ana").size.should == 1
    end

    it "removes a panel of member details that names no one" do
      panel = '<div class="message-userExtras"><dl><dt>Joined</dt><dd>Jan 2020</dd><dt>Location</dt>' \
              '<dd><a href="/location?q=Leeds">Leeds</a></dd></dl></div>'

      line(panel).should be_nil
      remaining(post(panel)).should_not include("Leeds")
    end

    it "keeps the post's date that a panel holds, not the member's" do
      panel = <<~HTML
        <div class="user-info">
          <div class="member-since">Member since <time datetime="2019-03-01">Mar 2019</time></div>
          <div class="user-action-time">answered <span class="relativetime">Jan 4, 2024</span></div>
          <div class="user-details" itemprop="author"><a href="/users/7/ana">Ana</a> <span class="reputation">2,301</span></div>
        </div>
      HTML

      line(panel).should == "Ana · answered Jan 4, 2024"
    end
  end

  describe "ids made from a heading's text" do
    let(:article) { "<h1>Selling on social media</h1>#{prose('Social selling', 4)}" }

    it "keeps headings and sections whose id is their heading's anchor" do
      html = <<~HTML
        #{article}
        <h2 class="wp-block-heading" id="h-what-is-social-shopping">What is social shopping?</h2>#{prose('Social shopping', 1)}
        <h3 id="sponsorship-deals-2">Sponsorship deals</h3>#{prose('Sponsorship', 1)}
        <section id="cookies"><h2>Cookies<a href="#cookies">¶</a></h2>#{prose('Reading cookies', 1)}</section>
      HTML

      text = remaining(html)
      text.should include("What is social shopping?")
      text.should include("Sponsorship deals")
      text.should include("Reading cookies is explained")
    end

    it "still removes junk labels, ids that are not anchors and furniture classes" do
      html = <<~HTML
        #{article}
        <h2 id="related-posts">Related posts</h2>
        <section id="share-this-article"><h3>Share this article</h3><a href="/share">Copy link</a></section>
        <section id="related-articles"><h2>Related articles<a href="#related-articles">¶</a></h2><a href="/older">Older story</a></section>
        <h3 id="social-links">Follow our journey</h3>
        <h2 class="social-title" id="h-social-media-tips">Social media tips</h2>
      HTML

      text = remaining(html)
      %w[Related Share Older Follow tips].each { |word| text.should_not include(word) }
    end
  end

  describe "repeated modules" do
    def cards(classes, count)
      Array.new(count) do |index|
        "<div class=\"#{classes}\"><a href=\"/story-#{index}\">Heat pump story #{index} headline with a few more words</a></div>"
      end.join
    end

    it "keeps a hub page made of modules named like recirculation widgets" do
      html = "<h1>Heat pumps</h1>#{cards('tax-sc__recirc-list-container', 8)}"

      text = remaining(html)
      text.should include("Heat pump story 0 headline")
      text.should include("Heat pump story 7 headline")
    end

    it "keeps cards that add a modifier to the run's classes" do
      html = "<h1>Heat pumps</h1><div class=\"recirc-item recirc-item--lead\"><a href=\"/lead\">Lead heat pump story</a></div>" \
             "#{cards('recirc-item', 7)}"

      remaining(html).should include("Lead heat pump story")
    end

    it "removes a rail that shares the cards' class" do
      rail = '<div class="recirc-module" id="right-rail-trending"><a href="/t">Trending elsewhere today</a></div>'
      text = remaining("<h1>Heat pumps</h1>#{cards('recirc-module', 6)}#{rail}")

      text.should include("Heat pump story 5 headline")
      text.should_not include("Trending elsewhere")
    end

    it "removes cookie categories however many there are" do
      categories = %w[Necessary Functional Analytics Advertising].map do |name|
        "<div class=\"wt-cli-cookie-description\">#{name} cookies store how visitors use the site, only with their consent.</div>"
      end
      html = "<h1>Opening hours</h1><p>We are open Monday to Friday.</p><div>#{categories.join}</div>"

      remaining(html).should_not include("cookies store")
    end

    it "removes a related rail beside an article" do
      html = "<article>#{prose('Sizing', 8)}</article>#{cards('related-card', 4)}"

      remaining(html).should_not include("Heat pump story")
    end

    it "counts wrappers that repeat their child's class once" do
      html = "<h1>Heat pumps</h1><div class=\"related\"><div class=\"related\"><div class=\"related\">#{cards('story', 2)}</div></div></div>"

      remaining(html).should == "Heat pumps"
    end

    it "removes menu items however many there are" do
      html = "<h1>Heat pumps</h1>#{cards('site-menu-item', 8)}"

      remaining(html).should == "Heat pumps"
    end
  end

  describe "taxonomy lines" do
    def article(url, meta)
      html = "<html><body><div class=\"entry\"><div><a href=\"/category/news/\">News</a></div><h1>Harbour</h1>" \
             "<p>By <a href=\"/author/ann/\">Ann</a> on 3 May</p>#{prose('The harbour', 3)}#{meta}</div></body></html>"
      Nokodown.to_markdown(html, url: url, title: false)
    end

    it "removes lines of links to the site's tag and category archives" do
      meta = '<p>Tags: <a href="/tag/boats/">boats</a>, <a href="https://www.example.com/tag/tides/">tides</a></p>' \
             '<p><span>Labels: <a href="/search/label/Sea" rel="tag">Sea</a></span></p>'
      markdown = article("https://example.com/2024/05/harbour/", meta)

      markdown.should start_with("# Harbour\n\nBy Ann on 3 May")
      %w[News boats tides Sea].each { |word| markdown.should_not include(word) }
    end

    it "keeps a line with other text, other links or another site's tags, and the lines of an archive itself" do
      meta = '<p>Filed in <a href="/category/news/">News</a> on 3 May by Ann</p>' \
             '<p>Tags: <a href="/tag/boats/">boats</a>, <a href="/boats-guide/">guide</a></p>' \
             '<p>See <a href="https://other.example/tag/tides/">tides</a></p>'
      markdown = article("https://example.com/2024/05/harbour/", meta)
      markdown.should include("Filed in News on 3 May by Ann")
      markdown.should include("boats")
      markdown.should include("tides")

      article("https://example.com/category/news/", "").should include("News")
    end

    it "keeps the category line of every card in a listing" do
      cards = %w[Bouldern Eisklettern Klettersteig].map do |name|
        "<div class='card'><h3><a href='/angebote/#{name.downcase}/'>#{name} course, two days</a></h3>" \
          "<p class='post-meta'><a href='/category/#{name.downcase}/' rel='tag'>#{name}</a></p><p>From 150 EUR</p></div>"
      end

      remaining("<h1>Courses</h1><div class='grid'>#{cards.join}</div>").should include("Eisklettern course, two daysEisklettern")
    end

    it "keeps a category line after the title, as a product's or an event's category is one of its facts" do
      meta = '<p>SKU: 212-3 <span class="posted_in">Category: <a href="/product-category/climbing/" rel="tag">Climbing</a></span> ' \
             'Kategorie <span><a href="/produkt/x/" rel="tag">Mosaik</a></span></p>' \
             '<p><span>Brand: <a href="/marca/dook/" rel="tag">Dook</a></span></p>'
      markdown = article("https://example.com/2024/05/harbour/", meta)

      markdown.should include("SKU: 212-3 Category: Climbing Kategorie Mosaik")
      markdown.should include("Brand: Dook")
    end

    it "keeps a product's facts linked to the filters of its category" do
      facts = { "Roof" => "gable", "Garage" => "double", "Floors" => "two" }.map do |name, value|
        "<div class='feature'><span>#{name}</span> <a href='/category/houses/#{value}/'>#{value}</a></div>"
      end

      remaining("<h1>House plan 12</h1>#{prose('The plan', 2)}<div class='features'>#{facts.join}</div>").should include("Roof gable")
    end
  end

  describe "blocks that hold the page's title" do
    it "keeps a block named like furniture that holds the page's only title and prose" do
      html = "<div class=\"dialog-off-canvas-main-canvas\"><h1>Visual identity</h1>#{prose('The logo', 1)}</div>" \
             "<div class=\"sidebar\"><p>Branding and web studio in Riyadh, open Sunday to Thursday.</p></div>"

      remaining(html).should include("Visual identity")
    end

    it "removes a sidebar headed by the site's name, and a trail or menu that holds the title" do
      studio = "<p>Branding and web studio in Riyadh, open Sunday to Thursday.</p>"
      sidebar = "<div class=\"sidebar\"><h1><a href=\"/\">Fikra</a></h1>#{studio}</div><h2>Visual identity</h2><p>Logos and type.</p>"
      trail = "<div class=\"breadcrumb\"><a href=\"/\">Home</a> <h1>Gallery</h1></div><img src=\"/1.jpg\"><p>Photos.</p>"

      remaining(sidebar).should_not include("Fikra")
      remaining(trail).should_not include("Home")
    end

    it "does not read the layout a list is laid out in as its name" do
      html = "<h1>News</h1>#{prose('The parade', 1)}<div class=\"posts-list one-right-sidebar\">#{prose('The jury', 2)}</div>" \
             "<div class=\"product-grid layout-sidebar-left\">#{prose('The costume', 2)}</div>"

      text = remaining(html)
      text.should include("The jury is explained")
      text.should include("The costume is explained")
    end
  end
end

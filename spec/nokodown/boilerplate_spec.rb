# frozen_string_literal: true

RSpec.describe Nokodown::Boilerplate do
  def cleaned(html)
    body = Nokolexbor::HTML("<html><body>#{html}</body></html>").at_css("body")
    Nokodown::Preprocessor.new(body).call
    Nokodown::Boilerplate.new(body).call
    body
  end

  # Text left by boilerplate removal alone, before the content is located.
  def remaining(html)
    Nokodown::Dom.text(cleaned(html))
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
             "<li><a href=\"mailto:?subject=Bonsai\">Envoyer</a></li></ul><p>Write to <a href=\"mailto:ana@ex.com\">Ana</a>.</p>"
      text = remaining(html)

      %w[シェア LinkedIn Envoyer].each { |label| text.should_not include(label) }
      text.should include("Write to Ana")
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
end

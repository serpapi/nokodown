# frozen_string_literal: true

RSpec.describe Nokodown::Boilerplate do
  # Text left by boilerplate removal alone, before the content is located.
  def remaining(html)
    body = Nokolexbor::HTML("<html><body>#{html}</body></html>").at_css("body")
    Nokodown::Preprocessor.new(body).call
    Nokodown::Boilerplate.new(body).call
    Nokodown::Dom.text(body)
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

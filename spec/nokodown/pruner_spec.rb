# frozen_string_literal: true

RSpec.describe Nokodown::Pruner do
  def content(html)
    root = Nokolexbor::HTML("<body><div class='story'>#{html}</div></body>").at_css("div.story")
    Nokodown::Dom.assign_keys(root)
    root
  end

  let(:story) do
    "<p>The harbor bridge reopened to traffic on Tuesday, three weeks after inspectors found cracked bearings.</p>" \
      "<p>Crews replaced six bearings and resurfaced both ramps, finishing four days early in the dry weather.</p>"
  end
  let(:teasers) do
    headlines = ["School board approves a new budget for next year", "Fishing season opens two weeks earlier than planned"]
    headlines.map do |headline|
      "<div class='card'><img src='/img/story.jpg' alt=''><h3><a href='/news/story'>#{headline}</a></h3></div>"
    end.join
  end
  let(:cards) do
    ["Cirrus Trail 3", "Scree Runner"].map do |name|
      "<div class='card'><img src='/img/shoe.jpg' alt=''><h3><a href='/products/shoe'>#{name}</a></h3>" \
        "<span>$129.00</span> <span>In stock, ships tomorrow</span></div>"
    end.join
  end

  describe "#conditional_share and #removed_link_share" do
    it "measure how much text conditional cleaning kept and how much of what it removed was links" do
      root = content(story + teasers)
      seen = Nokodown::Dom.text(root).length
      pruner = described_class.new([root], :article).call

      Nokodown::Dom.text(root).should_not include("School board")
      pruner.conditional_share.should == Nokodown::Dom.text(root).length.fdiv(seen)
      pruner.removed_link_share.should == 1.0
    end

    it "report that everything was kept when conditional cleaning did not run" do
      pruner = described_class.new([content(story + teasers)], :page).call

      pruner.conditional_share.should == 1.0
      pruner.removed_link_share.should == 0.0
    end
  end

  describe "footers by any name" do
    let(:report) do
      "#{story}<p>The city will repaint the railings next spring, when river traffic is light and scaffolding can hang over the water.</p>"
    end

    def pruned(html)
      root = content(html)
      described_class.new([root], :page).call
      Nokodown::Dom.text(root)
    end

    it "removes a footer-named block that ends the content" do
      %w[mFooter b-footer__row foot_section agriFooterWrapper].each do |name|
        pruned("#{report}<div class=\"#{name}\"><p>26 Park Road, Tel 031-730-3500</p></div>").should_not include("Park Road")
      end
    end

    it "keeps a footer-named block that more of the content follows" do
      pruned("<div class=\"box\"><p>Heat pumps</p><div class=\"meta-footer\">Installed by Ana Ruiz</div></div>#{report}").should include("Ana Ruiz")
    end

    it "keeps a block whose name says it is not a footer" do
      pruned("#{report}<div class=\"wsite-not-footer\"><p>Photos from the spring concert</p></div>").should include("spring concert")
    end

    it "keeps footers on a page with almost no text" do
      pruned("<p>Spring concert</p><div class=\"footer-wrap\"><img src=\"/concert.jpg\" alt=\"\"><p>Hall B</p></div>").should include("Hall B")
    end

    it "keeps the footer of the post that ends the content" do
      pruned("<div class=\"post\">#{report}<div class=\"post-footer\">Posted by Ana Ruiz at 12:32</div></div>").should include("Ana Ruiz")
    end

    it "looks inside a footer-named block that holds most of the content for the site's footer" do
      html = "<div class=\"footer_guideWrap\">#{report}<ul class=\"footer_guide_small\"><li>TEL 03-5817-0558</li></ul></div>"
      text = pruned(html)

      text.should include("harbor bridge")
      text.should_not include("5817")
    end

    it "keeps the notes that end the main landmark" do
      root = Nokolexbor::HTML("<body><main>#{report}<div id=\"section-footer\"><p>1. Tested to IEC 60529.</p></div></main></body>").at_css("main")
      Nokodown::Dom.assign_keys(root)
      described_class.new([root], :page).call

      Nokodown::Dom.text(root).should include("IEC 60529")
    end
  end

  describe "article pruning with conditional cleaning off" do
    let(:html) do
      "<p class='byline'>By Jo Pine</p>#{story}#{cards}" \
        "<h2>Related reading</h2><ul><li><a href='/guides/fit'>How to choose trail running shoes that fit</a></li>" \
        "<li><a href='/guides/plates'>Do you need a rock plate in your trail shoes?</a></li></ul>" \
        "<div><a href='/men'>Men</a> <a href='/women'>Women</a> <a href='/sale'>Sale</a></div>"
    end

    it "keeps the linky cards that conditional cleaning removes" do
      cleaned = content(html)
      described_class.new([cleaned], :article).call
      Nokodown::Dom.text(cleaned).should_not include("Cirrus Trail 3")

      root = content(html)
      described_class.new([root], :article, conditional: false).call
      Nokodown::Dom.text(root).should include("Cirrus Trail 3")
      Nokodown::Dom.text(root).should include("$129.00 In stock, ships tomorrow")
    end

    it "still drops the byline, the box of related links and the navigation" do
      root = content(html)
      described_class.new([root], :article, conditional: false).call
      text = Nokodown::Dom.text(root)

      ["Jo Pine", "Related reading", "How to choose", "Women"].each { |noise| text.should_not include(noise) }
    end
  end
end

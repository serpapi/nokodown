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

  describe "boilerplate text" do
    def pruned(html)
      root = content(story + html)
      described_class.new([root], :page).call
      root
    end

    it "removes the cart button of a card whose only words it is, but keeps the card's picture" do
      cards = %w[В\ корзину Add\ to\ cart].each_with_index.map do |label, index|
        "<div class='item'><a href='/p/#{index}'><img src='/img/#{index}.jpg' alt='Diamond bur'></a>" \
          "<div class='buy'><span class='btn'>#{label}</span></div></div>"
      end
      root = pruned("<div class='catalog'>#{cards.join}</div>")

      root.css("img").size.should == 2
      Nokodown::Dom.text(root).should_not match(/корзину|cart/)
    end

    it "removes the box of an advertisement's label with the banner it links" do
      root = pruned("<div class='box'><span>Advertisement</span><a href='/partners/acme-lab'><img src='/ads/acme.jpg' alt='Acme Lab'></a></div>" \
                    "<div class='box'><span>Sponsored</span><a href='https://acme.example'><img src='/ads/sale.jpg' alt='Sale'></a></div>")

      root.css("img").should be_empty
    end

    it "removes an icon in the label's own element and a logo that links home" do
      root = pruned("<div><a href='https://twitter.com/intent/tweet'><img src='/x.svg' alt=''> Share</a></div>" \
                    "<div><a href='/'><img src='/logo.png' alt='Acme'></a><span>Skip to content</span></div>")

      root.css("img").should be_empty
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

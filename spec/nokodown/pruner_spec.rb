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

  describe "secondary regions" do
    it "removes adjacent ones and those nested in kept elements" do
      root = content("#{story}<div class='comments'><p>First!</p></div><div class='tags'><a href='/t/bridges'>bridges</a></div>" \
                     "<div class='wrap'><p>Crews worked nights to finish early.</p><div class='popular'><p>Most read today</p></div></div>")
      described_class.new([root], :article, conditional: false).call
      text = Nokodown::Dom.text(root)

      ["First!", "bridges", "Most read today"].each { |noise| text.should_not include(noise) }
      text.should include("Crews worked nights")
    end
  end

  describe "stray lines and boilerplate text" do
    it "measures them after squishing, so indentation does not hide them" do
      pad = "\n#{' ' * 150}\t\n"
      root = content("#{story}<div>#{pad}Published on March 3, 2024#{pad}</div><span>#{pad}Advertisement#{pad}</span>" \
                     "<p>#{pad}Follow us on Twitter and Facebook for updates.#{pad}</p>" \
                     "<table><tr><td><div>Updated 4 March 2024</div></td></tr></table>")
      described_class.new([root], :article, conditional: false).call
      text = Nokodown::Dom.text(root)

      ["Published on", "Advertisement", "Follow us"].each { |noise| text.should_not include(noise) }
      text.should include("Updated 4 March 2024")
      text.should include("Crews replaced six bearings")
    end
  end

  describe "calls to action" do
    it "removes buttons of each holder tag, nested ones too, finding them with one XPath query" do
      root = content("#{story}<div class='btn-primary'><a class='button' href='/buy'>Buy now</a></div>" \
                     "<p><span class='cta'>Sign up</span></p><p class='btn'>Book a demo</p>" \
                     "<p>Read the <a class='btn-link' href='/report'>full report</a> online.</p>")
      root.should_not_receive(:css)
      described_class.new([root], :article, conditional: false).send(:remove_calls_to_action, root)
      text = Nokodown::Dom.text(root)

      ["Buy now", "Sign up", "Book a demo"].each { |noise| text.should_not include(noise) }
      text.should include("Read the full report online.")
      text.should include("Crews replaced six bearings")
    end
  end

  describe "#button?" do
    it "reads the button words in the class or id in any case, without downcasing them" do
      root = content("<a class='Hero BTN-Primary'>a</a><span id='mainCTA' class='Btn'>b</span><a class='lead'>c</a>" \
                     "<span id='notes'>d</span><p class='bt' id='n'>e</p><a class='button-link'>f</a><b role='button'>g</b>")
      pruner = described_class.new([root], :article, conditional: false)
      downcased = 0
      trace = TracePoint.new(:c_call) { |point| downcased += 1 if point.method_id == :downcase }
      quiet = trace.enable { root.css("a.lead, span#notes, p.bt").map { |node| pruner.send(:button?, node) } }

      quiet.should == [false, false, false]
      downcased.should == 0
      root.element_children.map { |node| pruner.send(:button?, node) }.should == [true, true, false, false, false, false, true]
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

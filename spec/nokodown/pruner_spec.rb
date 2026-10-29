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

  describe "page pruning" do
    let(:urls) { Nokodown::UrlResolver.new("https://example.com/page") }
    let(:rail) do
      places = %w[
        Bagienice Barczewko Barczewo Barkweda Bartag Bartazek Bartolty Bezled Biskupiec Bisztynek Blanki Boguchwaly
        Bredynki Brzeznica Bukwald Butryny Cerkiewnik Czarny Dadaj Dobre Dorotowo Dywity Gady Gietrzwald Gradki
        Jeziorany Jonkowo Kaplityny Klebark Kolno Lamkowo Lelkowo Lidzbark Lukta Majdy Mragowo Naterki Olsztynek
      ]
      places.map { |place| "<a href='/places/#{place.downcase}'>#{place}</a><br>" }.join
    end

    it "keeps a line of names that links to the page itself among names without links" do
      authors = "<p>By <a href='/page'>Ana Ruiz</a>, Ben Ode, <a href='/people/cole'>Cy Cole</a>, Dee Fox and " \
                "<a href='/people/lin'>Eve Lin</a></p>"
      root = content(story * 2 + authors)

      described_class.new([root], :page, urls: urls).call

      Nokodown::Dom.text(root).should include("Ben Ode, Cy Cole, Dee Fox")
    end

    it "drops the whole box of links around a menu that links to the page itself" do
      tags = "Tagged: <a href='/tags/tide'>Tide</a>, <a href='/page'>Energy</a>, <a href='/tags/sea'>Sea</a>"
      meta = "<div><a href='/c/coast'>Coastal engineering</a> <a href='/c/power'>Renewable power</a> <span>#{tags}</span></div>"
      root = content((story + meta) * 3)

      described_class.new([root], :page, urls: urls).call

      Nokodown::Dom.text(root).should include("The harbor bridge reopened")
      ["Coastal engineering", "Tide", "Sea"].each { |noise| Nokodown::Dom.text(root).should_not include(noise) }
    end

    it "keeps a listing column that its layout table declares wider than the column beside it" do
      rows = %w[Vector Rapid Alpine Corsa Delta Falcon].map do |name|
        "<tr><td><a href='/wheels/#{name.downcase}'>#{name} R16 alloy wheel, 7J ET40</a></td><td>4,200 rub.</td></tr>"
      end
      contact = "<p>Orders by phone from ten to seven every day, pick-up from our warehouse in Lyubertsy, " \
                "delivery the next day.</p>"
      root = content("#{story}<table><tr><td><table>#{rows.join}</table></td><td width='160'>#{contact}</td></tr></table>")

      described_class.new([root], :page, urls: urls).call

      Nokodown::Dom.text(root).should include("Falcon R16 alloy wheel")
    end

    it "drops a column declared narrower than the prose beside it, even when its links hold most of the text" do
      root = content("<table><tr><td width='190'>#{rail}</td><td width='560'>#{story}</td></tr></table>")

      described_class.new([root], :page, urls: urls).call

      Nokodown::Dom.text(root).should include("The harbor bridge reopened")
      Nokodown::Dom.text(root).should_not include("Bisztynek")
    end

    it "judges a page whose side column made it look like an index again without that column" do
      menu = %w[Home About Contact].map { |name| "<li><a href='/#{name.downcase}'>#{name}</a></li>" }.join
      root = content("<table><tr><td width='190'>#{rail}</td><td width='560'><ul>#{menu}</ul>#{story}</td></tr></table>")

      described_class.new([root], :page, urls: urls).call

      Nokodown::Dom.text(root).should_not include("Contact")
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

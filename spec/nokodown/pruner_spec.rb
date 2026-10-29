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

    it "judges a list once however many of its links lead to the page itself" do
      entries = (1..500).map { |number| "<li><a href='/page'>Item #{number}</a> (#{number})</li>" }.join
      root = content("#{story}<ul>#{entries}</ul>")
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      described_class.new([root], :page, urls: urls).call

      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).should < 1
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

    describe "headings over a box of links it drops" do
      let(:share) do
        "<ul><li><a href='/share/email'>Email</a></li><li><a href='/share/twitter'>Twitter</a></li>" \
          "<li><a href='/share/facebook'>Facebook</a></li></ul>"
      end

      def pruned(html)
        root = content(story + html)
        described_class.new([root], :page, urls: urls).call
        root
      end

      it "drops a heading that labels nothing else" do
        root = pruned("<div><h3>Elsewhere</h3>#{share}</div><div><h3>About us</h3><p>A small team.</p></div>")

        root.inner_html.should_not include("Elsewhere")
        root.inner_html.should include("About us")
      end

      it "drops the lead that ends in a colon before the box" do
        ["<span>Find us on:</span> #{share}", "Find us on: #{share}"].each do |html|
          Nokodown::Dom.text(pruned("<div>#{html}</div>")).should_not include("Find us")
        end
      end

      it "keeps a header that holds more than a lead before the box" do
        root = pruned("<div><div>Tag: Ant games Show: Sort:</div>#{share}</div>")

        Nokodown::Dom.text(root).should include("Tag: Ant games")
      end

      it "keeps a heading whose section holds text beside the box" do
        hours = "Monday to Friday, nine to five, closed on public holidays."
        ["<h3>Opening hours</h3>#{hours}<div>#{share}</div>", "<h3>Opening hours</h3><div>#{hours} #{share}</div>",
         "<div><h3>Opening hours</h3>#{share} #{hours}</div>"].each do |html|
          pruned(html).inner_html.should include("Opening hours")
        end
      end

      it "keeps a card's title when the card's details follow in a row of their own" do
        tags = "Categories: <a href='/fields/albany'>Albany</a>, <a href='/page'>Nose</a>, " \
               "<a href='/fields/throat'>Throat</a>"
        card = "<div><h2>AMC Otolaryngology</h2><small>#{tags}</small></div><div>Address: 35 Hackett Boulevard</div>"

        pruned(card).inner_html.should include("AMC Otolaryngology")
      end

      it "keeps a linked heading" do
        agent = "<a href='/agents/144'><h5>Gurhan Altunsoy</h5></a>#{share}"

        pruned(agent).inner_html.should include("Gurhan Altunsoy")
      end

      it "keeps the titles of a run of cards over their tags" do
        cards = %w[Handles Bins Drawers].map do |name|
          "<div class='card'><h5>#{name}</h5><span><a href='/c/kitchen'>Kitchen</a>, <a href='/c/steel'>Steel</a>, " \
            "<a href='/c/#{name.downcase}'>#{name}</a></span></div>"
        end

        pruned(cards.join).css("h5").map(&:text).should == %w[Handles Bins Drawers]
      end

      it "keeps the page title" do
        pruned("<div><h1>Spring sale</h1>#{share}</div><h2>Delivery</h2>").inner_html.should include("Spring sale")
      end

      it "counts a CJK character in a label as a short word" do
        tags = %w[東京 大阪 京都].map { |city| "<a href='/tags/#{city}'>#{city}</a>" }.join(" ")
        title = "東武伊勢崎線沿線の新しい温泉旅館を訪ねて"

        pruned("<div><h4>#{title}</h4><div>#{tags}</div></div><h2>次の記事</h2>").inner_html.should include(title)
      end
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

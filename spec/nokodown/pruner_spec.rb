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

    it "keeps a teaser's short linked title with its date and author links, not a menu of linked headings" do
      teaser = "<header><h2><a href='/archives/42822'>ショップが新しくなりました</a></h2>" \
               "<a href='/archives/42822'>2021年03月09日</a> <a href='/author/micasa'>micasa</a></header>"
      menu = "<div><h3><a href='/men'>Men</a></h3><h3><a href='/women'>Women</a></h3><h3><a href='/sale'>Sale</a></h3></div>"
      root = content(teaser + story + menu)
      described_class.new([root], :page).call
      text = Nokodown::Dom.text(root)

      text.should include("ショップが新しくなりました2021年03月09日 micasa")
      text.should_not include("Women")
    end

    it "drops a menu or a widget under a single linked heading" do
      menu = "<div><h4><a href='/shop'>Shop</a></h4>" + %w[Men Women Kids Sale].map { |name| "<a href='/#{name}'>#{name}</a> " }.join + "</div>"
      icons = "<div><h3><a href='/login'>Login</a></h3>" + %w[x fb ig].map { |name| "<a href='https://#{name}.example'><img src='/#{name}.svg'></a>" }.join + "</div>"
      root = content(story + menu + icons)
      described_class.new([root], :page).call
      text = Nokodown::Dom.text(root)

      text.should_not include("Women")
      text.should_not include("Login")
    end

    it "keeps a line of names that links to the page itself among names without links" do
      authors = "<p>By <a href='/page'>Ana Ruiz</a>, Ben Ode, <a href='/people/cole'>Cy Cole</a>, Dee Fox and " \
                "<a href='/people/lin'>Eve Lin</a></p>"
      root = content(story * 2 + authors)

      described_class.new([root], :page, urls: urls).call

      Nokodown::Dom.text(root).should include("Ben Ode, Cy Cole, Dee Fox")
    end

    it "keeps links that a sentence names" do
      plans = "<span><a href='/plans/standard'>Standard</a>, <a href='/plans/premium'>Premium</a> or <a href='/plans/gold'>Gold</a></span>"
      root = content(story + "<div>Want a discount? Become a member by purchasing #{plans}!</div>")

      described_class.new([root], :page, urls: urls).call

      Nokodown::Dom.text(root).should include("purchasing Standard, Premium or Gold!")
    end

    it "drops the whole box of links around a menu that links to the page itself" do
      tags = "Tagged: <a href='/tags/tide'>Tide</a>, <a href='/page'>Energy</a>, <a href='/tags/sea'>Sea</a>"
      meta = "<div><a href='/c/coast'>Coastal engineering</a> <a href='/c/power'>Renewable power</a> <span>#{tags}</span></div>"
      root = content((story + meta) * 3)

      described_class.new([root], :page, urls: urls).call

      Nokodown::Dom.text(root).should include("The harbor bridge reopened")
      ["Coastal engineering", "Tide", "Sea"].each { |noise| Nokodown::Dom.text(root).should_not include(noise) }
    end

    it "drops the rest of a post's meta line once its tags that link to the page itself are gone" do
      tags = "<span>Tagged <a href='/tags/arizona'>Arizona</a>, <a href='/tags/art'>art</a>, " \
             "<a href='/page'>Jeep</a>, <a href='/tags/navajo'>Navajo</a></span>"
      meta = "<footer><span>Posted in <a href='/c/days'>Days in My Life</a>, " \
             "<a href='/c/travels'>Travels with Maria</a></span> | #{tags} | " \
             "<a href='/post#comments'>6 Comments</a></footer>"
      root = content("<article><h2>A rug from Arizona</h2>#{story}#{meta}</article>" * 3)

      described_class.new([root], :page, urls: urls).call

      Nokodown::Dom.text(root).should include("The harbor bridge reopened")
      ["Travels with Maria", "Navajo", "6 Comments"].each { |noise| Nokodown::Dom.text(root).should_not include(noise) }
    end

    it "drops the list a submenu that links to the page itself hung from" do
      submenu = "<ul><li><a href='/c/signs/info'>Information signs</a></li><li><a href='/page'>Warning signs</a></li>" \
                "<li><a href='/c/signs/works'>Regulatory signs for highway works</a></li></ul>"
      categories = %w[Bollards Barriers Cones Paint].map { |name| "<li><a href='/c/#{name}'>#{name}</a></li>" }.join
      sidebar = "<div><h4>Product categories</h4>" \
                "<ul>#{categories}<li><a href='/c/signs'>Signs</a>#{submenu}</li></ul></div>"
      root = content(story + sidebar)

      described_class.new([root], :page, urls: urls).call

      Nokodown::Dom.text(root).should include("The harbor bridge reopened")
      ["Bollards", "Product categories"].each { |noise| Nokodown::Dom.text(root).should_not include(noise) }
    end

    it "keeps a run of cards whose category lines link to the page itself" do
      terms = "<span><a href='/page'>2024</a>, <a href='/c/budget'>Commission on planning, budget and finance</a>, " \
              "<a href='/c/minutes'>Minutes</a></span>"
      cards = (1..5).map do |number|
        "<article><div><header><p>#{terms}</p><h2><a href='/minutes/#{number}'>Minutes #{number}</a></h2>" \
          "<ul><li>07.01.2025</li><li><a href='/author/admin'>Admin</a></li></ul></header>" \
          "<p><a href='/minutes/#{number}'>Continue reading</a></p></div></article>"
      end
      root = content("<h1>2024</h1>#{story}#{cards.join}")

      described_class.new([root], :page, urls: urls).call

      ["Minutes 1", "Minutes 5", "Admin"].each { |kept| Nokodown::Dom.text(root).should include(kept) }
      Nokodown::Dom.text(root).should_not include("Commission on planning")
    end

    it "drops the links beside a menu whose label or entries were the only headings around it" do
      menu = { "/c/works" => "Regulatory signs for highway works", "/page" => "Warning", "/c/info" => "Info" }
      items = menu.map { |href, text| "<li><a href='#{href}'>#{text}</a></li>" }.join
      titles = menu.map { |href, text| "<h3><a href='#{href}'>#{text}</a></h3>" }.join
      links = "<p><a href='/a'>Alpha</a> <a href='/b'>Beta</a></p><p><a href='/c'>Gamma</a></p>"

      ["<div><h4>Categories</h4><ul>#{items}</ul></div>", "<div>#{titles}</div>"].each do |box|
        root = content("#{story}<div class='sidebar'>#{links}#{box}</div>")

        described_class.new([root], :page, urls: urls).call

        Nokodown::Dom.text(root).should include("The harbor bridge reopened")
        ["Alpha", "Gamma"].each { |noise| Nokodown::Dom.text(root).should_not include(noise) }
      end
    end

    it "drops the links beside each menu set in the clones of a font left open, which share one key" do
      menu = "<span><a href='/c/works'>Regulatory signs for highway works</a>, <a href='/page'>Warning</a>, " \
             "<a href='/c/info'>Info</a></span>"
      links = "<p><a href='/a'>Alpha</a> <a href='/b'>Beta</a></p><p><a href='/c'>Gamma</a></p>"
      root = content("#{story}<div><p><font face='Verdana'>#{menu}</p></div><div><p>#{menu}</p>#{links}</div>")

      described_class.new([root], :page, urls: urls).call

      Nokodown::Dom.text(root).should include("The harbor bridge reopened")
      ["Alpha", "Gamma"].each { |noise| Nokodown::Dom.text(root).should_not include(noise) }
    end

    it "judges a list once however many of its links lead to the page itself" do
      entries = (1..500).map { |number| "<li><a href='/page'>Item #{number}</a> (#{number})</li>" }.join
      root = content("#{story}<ul>#{entries}</ul>")
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      described_class.new([root], :page, urls: urls).call

      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).should < 1
    end

    it "judges a long table once, however many of its rows hold prose beside links" do
      prose = "A long sentence of prose that describes the item in some detail and goes on for a while."
      rows = (1..2000).map do |number|
        "<tr><td>#{prose} #{number}</td><td><a href='/a#{number}'>x</a> <a href='/b#{number}'>y</a> <a href='/c#{number}'>z</a></td></tr>"
      end
      root = content("<table>#{rows.join}</table>")
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      described_class.new([root], :page, urls: urls).call

      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).should < 3
    end

    it "drops a narrow grid column of links beside the column that holds the title" do
      %w[span4/span8 col-xs-12\ col-md-4/col-xs-12\ col-md-8 td-pb-span4/td-pb-span8].each do |pair|
        side, main = pair.split("/")
        root = content("<div class='row'><div class='#{main}'><h1>Bridge</h1>#{story}</div><div class='#{side}'>#{rail}</div></div>")

        described_class.new([root], :page, urls: urls).call

        Nokodown::Dom.text(root).should include("cracked bearings")
        Nokodown::Dom.text(root).should_not include("Bisztynek")
      end
    end

    it "drops the side-named cells of a portal's layout table" do
      root = content("<table><tr><td class='side-border-left'>#{rail}</td><td class='main-bg'>#{story}</td></tr></table>")

      described_class.new([root], :page, urls: urls).call

      Nokodown::Dom.text(root).should_not include("Bisztynek")
    end

    it "keeps a narrow grid column with little link text, and one beside a wide column without the title or prose" do
      price = "<div class='col-md-4'><p>Price: 129 EUR, in stock, ships in two days.</p><a href='/cart'>Add to cart</a></div>"
      root = content("<div class='row'><div class='col-md-8'><h1>Trail shoe</h1>#{story}</div>#{price}</div>")
      described_class.new([root], :page, urls: urls).call
      Nokodown::Dom.text(root).should include("Price: 129 EUR")

      root = content("<div class='row'><div class='span8'>#{story}</div><div class='span4'><h1>Places</h1>#{rail}</div></div>")
      described_class.new([root], :page, urls: urls).call
      Nokodown::Dom.text(root).should include("Bisztynek")

      guides = %w[Moving Separating Retiring].map { |name| "<li><a href='/guides/#{name.downcase}'>#{name}: what to do</a></li>" }.join
      root = content("<div class='row'><div class='col-md-8'><ul>#{guides}</ul></div><div class='col-md-4'>#{rail}</div></div>")
      described_class.new([root], :page, urls: urls).call
      Nokodown::Dom.text(root).should include("Bisztynek")
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

      it "keeps a banner that holds a picture beside its heading" do
        banner = "<div><img src='/img/cases.jpg' alt='Our cases'><h3>Cases</h3></div>"

        pruned("#{banner}<div>#{share}</div><h2>Workshop</h2>").css("img").size.should == 1
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

  describe "pagers and calendars" do
    it "drops page numbers whose current number is plain text, on any page" do
      numbers = (1..47).map { |number| number == 3 ? "<b>3</b>" : "<a href='/list?page=#{number}'>#{number}</a>" }
      pager = "<div class='nav'>Pages: <a href='/list?page=2'>«</a> #{numbers.join(' ')} <a href='/list?page=4'>Next ›</a></div>"
      %i[page article].each do |mode|
        root = content("#{story}#{pager}")

        described_class.new([root], mode).call

        Nokodown::Dom.text(root).should_not include("Pages")
        Nokodown::Dom.text(root).should include("cracked bearings")
      end
    end

    it "drops an archive calendar of day links" do
      weeks = (1..30).each_slice(7).map { |days| "<tr>#{days.map { |day| day.odd? ? "<td><a href='/2026/04/#{day}'>#{day}</a></td>" : "<td>#{day}</td>" }.join}</tr>" }
      calendar = "<table><caption>April 2026</caption><tr>#{%w[Mo Tu We Th Fr Sa Su].map { |day| "<th>#{day}</th>" }.join}</tr>" \
                 "#{weeks.join}<tfoot><tr><td><a href='/2026/03'>« March</a></td></tr></tfoot></table>"
      root = content("#{story}#{calendar}")

      described_class.new([root], :page).call

      Nokodown::Dom.text(root).should_not include("April")
    end

    it "keeps numbers in a sentence, footnote marks and a short run" do
      notes = (1..6).map { |number| "<a href='#fn#{number}'>#{number}</a>" }.join(" ")
      html = "#{story}<p>See notes #{notes} below.</p><p><a href='/p/1'>1</a> <a href='/p/2'>2</a> <a href='/p/3'>3</a></p>"
      root = content(html)

      described_class.new([root], :page).call

      Nokodown::Dom.text(root).should include("See notes 1 2 3 4 5 6 below.")
      Nokodown::Dom.text(root).should end_with("1 2 3")
    end
  end

  describe "links within the page" do
    let(:faq) do
      questions = ["How do I register?", "Can I change my name?", "Why was my post removed?"]
      toc = questions.each_with_index.map { |question, index| "<li><a href='#q#{index}'>#{question}</a></li>" }.join
      answers = questions.each_with_index.map do |question, index|
        "<h3 id='q#{index}'>#{question}</h3><p>Answer #{index}: the forum explains this at length in a paragraph.</p>" \
          "<p><a href='#faqtop'>Back to top</a></p>"
      end
      "<a name='faqtop'></a><h2>Contents</h2><ul>#{toc}</ul>#{answers.join}"
    end

    it "drops a table of contents and the links back to the top" do
      %i[page article].each do |mode|
        root = content("#{story}#{faq}")

        described_class.new([root], mode).call

        text = Nokodown::Dom.text(root)
        text.scan("How do I register?").size.should == 1
        text.should include("Answer 2")
        text.should_not include("Back to top")
        text.should_not include("Contents")
      end
    end

    it "keeps footnote marks, back-references and questions that open their answers" do
      notes = "<p>The bridge reopened.<sup><a href='#n1'>1</a></sup> Crews worked fast.<sup><a href='#n2'>2</a></sup></p>" \
              "<ol><li id='n1'><a href='#r1'>↑</a> City press release, May 2026.</li>" \
              "<li id='n2'><a href='#r2'>↑</a> Interview with the site manager.</li></ol>"
      accordion = "<div id='a1'><a href='#a1'>Opening hours</a><div>From six to ten every day.</div></div>"
      root = content("#{story}#{notes}#{accordion}")

      described_class.new([root], :page).call

      text = Nokodown::Dom.text(root)
      text.should include("reopened.1")
      text.should include("↑ City press release")
      text.should include("Opening hours")
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

    it "keeps the notes that end the main landmark or an article" do
      ["<main>", "<div role=\"main\">", "<article>", "<div itemprop=\"articleBody\">"].each do |landmark|
        root = content("<div>#{landmark}#{report}<div class=\"foot\"><p>1. Tested to IEC 60529.</p></div></div></div>")
        described_class.new([root], :page).call

        Nokodown::Dom.text(root).should include("IEC 60529")
      end
    end

    it "keeps the footer of a unit, a quote or a section, and a footnote" do
      ends = [
        "<div class=\"table-footer\">Prices include VAT.</div>",
        "<section><div class=\"card\"><p>Bulk orders</p><footer class=\"card-footer\">Call sales on 555-0100.</footer></div></section>",
        "<section><blockquote><p>The best kettle I own.</p><footer>Jane Doe, mountain guide</footer></blockquote></section>",
        "<section><h2>Opening hours</h2><footer>Closed on public holidays.</footer></section>",
        "<div class=\"FootNote\"><p>* Prices exclude shipping to the islands.</p></div>"
      ]
      ends.each { |tail| pruned(report + tail).should end_with(Nokodown::Dom.text(content(tail).children.last)) }
    end

    it "removes a footer element when its section wraps the page" do
      pruned("<section>#{report}<footer><p>26 Park Road, Tel 031-730-3500</p></footer></section>").should_not include("Park Road")
    end

    it "walks back over a thread of thousands of footers in one section in time linear in its text" do
      post = "<div class=\"comment\"><p>#{'The ferry was late again, and the queue reached the harbour gate. ' * 16}</p><footer>Reply</footer></div>"
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      text = pruned("<section>#{post * 5000}</section>")

      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).should < 2
      text.should start_with("The ferry was late again")
    end

    it "does not read a shop category's name as a footer" do
      products = %w[Insoles Separators Splint Socks].map do |name|
        "<li class=\"product type-product product_cat-foot-care\"><h2>#{name}</h2><p>Soft support for tired feet, $19.00</p></li>"
      end
      pruned("#{report}<ul class=\"products\">#{products.join}</ul>").should include("Socks")
    end
  end

  describe "copyright lines" do
    def pruned(html)
      root = content(html)
      described_class.new([root], :page).call
      Nokodown::Dom.text(root)
    end

    it "removes them in other languages, with licence numbers, and from a layout table" do
      lines = [
        "<p>Alle Rechte vorbehalten. Deutscher Baseball Verband 2005</p>",
        "<div>互联网药品信息服务资格证书 | 冀ICP备17031426号</div>",
        "<table><tr><td>© анекдотов.net, 1997 - 2026</td></tr></table>",
        "<font color=\"999999\">Copyright &copy; 2026 By <a href=\"/\">Showlive</a> All Rights Reserved.</font>",
        "<p>| Copyright 2026 Harbor Times</p>"
      ]
      lines.each { |line| pruned(story + line).should end_with("dry weather.") }
    end

    it "keeps text about copyright and licence filings" do
      lines = [
        "<h2>ICP备案需要哪些材料？</h2>",
        "<p>本网站上刊登的文章、照片及其他一切著作物的版权归本公司（版权所有者）所有。</p>",
        "<table><tr><td>(c) to allow the landlord access to the flat for repairs</td></tr></table>"
      ]
      lines.each { |line| pruned(story + line).should end_with(Nokodown::Dom.text(content(line))) }
    end

    it "removes the line but not a product that shares its block" do
      html = "<div><div><h1>iTunes 500 SAR</h1><p>Out of stock</p><p>$1.112</p></div><div><p>جميع الحقوق محفوظة، الأمين</p></div></div>"
      text = pruned(html)

      text.should include("$1.112")
      text.should_not include("محفوظة")
    end

    it "removes the links and numbers that share the line's block" do
      line = "<div><span>21064736</span><p>Harbor Times 2026. All rights reserved.</p><a href=\"/privacy\">Privacy</a> | <a href=\"/terms\">Terms</a></div>"

      pruned(story + line).should end_with("dry weather.")
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

    def titled(title, html)
      root = Nokolexbor::HTML("<html><head><title>#{title} - Talking Canberra</title></head>" \
                              "<body><div class='story'>#{story}#{html}</div></body></html>").at_css("div.story")
      Nokodown::Dom.assign_keys(root)
      described_class.new([root], :article, conditional: false).call
      Nokodown::Dom.text(root)
    end

    it "drops the line a feed adds naming the post and the site it appeared on first" do
      lines = {
        "Man missing from unit" => "<p>The post <a href='https://radio.example.com/?p=4127'>Man missing from unit</a> " \
                                   "appeared first on <a href='https://radio.example.com/'>Talking Canberra</a>.</p>",
        "Врач призвал привиться" => "<p>Сообщение <a href='https://news.example.ru/общество/врач-призвал/'>Врач призвал " \
                                    "привиться</a> появились сначала на <a href='https://news.example.ru'>Новости</a>.</p>"
      }
      lines.each do |title, line|
        text = titled(title, line)

        text.should_not include(title)
        text.should end_with("dry weather.")
      end
    end

    it "keeps a photo's credit, which names its author" do
      credit = "<p>Image by <a href='https://photos.example.com/users/susan-7009216/'>Susan Cipriano</a> from " \
               "<a href='https://photos.example.com/'>Photos</a></p>"

      titled("Man missing from unit", credit).should include("Susan Cipriano")
    end

    it "keeps a line like a feed's that goes on after its links" do
      line = "<p>Read <a href='https://radio.example.com/news/missing-man/'>Man missing from unit</a> on " \
             "<a href='https://radio.example.com/'>our site</a>, then vote.</p>"

      titled("Man missing from unit", line).should include("then vote")
    end

    it "keeps a line like a feed's whose links lead to two sites" do
      line = "<p>The post <a href='https://radio.example.com/news/missing-man/'>Man missing from unit</a> is " \
             "kept on <a href='https://archive.example.org/'>the archive</a>.</p>"

      titled("Man missing from unit", line).should include("the archive")
    end

    it "drops a line that holds nothing but a label and the link after it" do
      root = content("#{story}<div class='see-also'>👉 <strong>Siehe auch:</strong> <a href='/news/9'>Ferry fares rise again</a></div>")
      described_class.new([root], :article, conditional: false).call

      Nokodown::Dom.text(root).should_not include("Ferry fares")
    end

    it "reads a label after the icon that leads it" do
      root = content("#{story}<p>📖 Lire aussi : <a href='/news/8'>Port strike ends after two weeks of talks</a></p>")
      described_class.new([root], :article, conditional: false).call

      Nokodown::Dom.text(root).should_not include("Port strike")
    end

    it "drops links to other stories under a label in the page's language" do
      labels = ["Lea también:", "Читайте также:", "İlgili Haberler:", "Baca juga:", "関連記事", "اقرأ أيضاً:"]
      boxes = labels.map { |label| "<p><strong>#{label}</strong> <a href='/news/9'>Ferry fares rise again in the spring</a></p>" }
      root = content(story + boxes.join)
      described_class.new([root], :article, conditional: false).call

      Nokodown::Dom.text(root).should_not include("Ferry fares")
    end
  end
end

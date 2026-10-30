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
  end
end

# frozen_string_literal: true

RSpec.describe Nokodown::ReadMoreLinks do
  def prune(html)
    root = Nokolexbor::HTML("<body><div class='list'>#{html}</div></body>").at_css("div.list")
    Nokodown::Dom.assign_keys(root)
    described_class.new(root).call
    root
  end

  def text_after(html)
    Nokodown::Dom.text(prune(html))
  end

  def card(title, extra)
    "<article><h2><a href='/posts/#{title.length}'>#{title}</a></h2><p>A short excerpt of the post…</p>#{extra}</article>"
  end

  it "removes a short link to the page the card's title links to, in any language" do
    html = card("The harbor bridge reopens", "<p><a href='/posts/25'>Leer más »</a></p>") +
           card("Crews finish early", "<a href='https://example.com/posts/18'>Details</a><a href='/posts/18'>詳細を見る</a>")
    text_after(html).should == "The harbor bridge reopensA short excerpt of the post…" \
                               "Crews finish earlyA short excerpt of the post…Details"
  end

  it "keeps a link inside a sentence, a date and a link to another page" do
    html = card("The harbor bridge reopens", "<p>Read it <a href='/posts/25'>here</a> today.</p>" \
                                             "<a href='/posts/25'>May 2, 2026</a><a href='/about'>About</a>")
    text_after(html).should end_with("Read it here today.May 2, 2026About")
  end

  it "keeps a badge before the title and a link whose page only a definition term names" do
    html = "<article><a href='/films/7'>HD</a><h3><a href='/films/7'>Reboot the Earth</a></h3></article>" \
           "<dl><dt><a href='/grease/59'>Lithium grease, 1 kg</a></dt><dd>For bearings. <a href='/grease/59'>Details</a></dd></dl>"
    text_after(html).should == "HDReboot the EarthLithium grease, 1 kgFor bearings. Details"
  end

  it "keeps a short link when the longer link to its page is in another card" do
    html = card("The harbor bridge reopens", "") + "<article><p>#{'Ferry times change. ' * 90}</p></article>" \
                                                   "<p><a href='/posts/25'>Read more</a></p>"
    text_after(html).should end_with("Read more")
  end

  it "keeps an item's name when the longer link to its page is a thumbnail or a date" do
    html = "<li><a href='/vod/1'><img src='/1.jpg'><span>Episode 54 added</span></a><div><a href='/vod/1'>Pokémon</a></div></li>" \
           "<li><a href='/hats/2'><img src='/2.jpg' alt='Wool hat'><span>Free shipping</span></a><div><a href='/hats/2'>Wool hat</a></div></li>" \
           "<div><a href='/game/3'><div>15 September, 19:00</div></a><div><a href='/game/3'>Bunker</a></div></div>"
    text_after(html).should == "Episode 54 addedPokémonFree shippingWool hat15 September, 19:00Bunker"
  end

  it "removes a label after a title inside the thumbnail's link" do
    html = "<article><a href='/posts/7'><img src='/7.jpg' alt=''><h3>The harbor bridge reopens</h3></a><p><a href='/posts/7'>Read more</a></p></article>"
    text_after(html).should == "The harbor bridge reopens"
  end

  it "keeps a label when the longer link around blocks is one Markdown does not write" do
    teams = "<p><span>Leones</span><img src='/leones.png' alt='Leones'></p><div><p>VS</p></div><p><span>Osos</span><img src='/osos.png' alt='Osos'></p>"
    html = "<div class='match'><a href='/cup/1'>#{teams}</a><p><a href='/cup/1'>Finished</a></p></div>" \
           "<div class='match'><a href='/cup/2'><p>Tigres against Lobos</p><p>VS</p></a><p><a href='/cup/2'>Details</a></p></div>"
    text_after(html).should == "LeonesVSOsosFinishedTigres against LobosVS"
  end

  it "keeps a label when the longer link wraps a paragraph too long for a title" do
    passage = "The bridge over the inner basin opens again on Monday after three months of repairs. " * 4
    html = "<div class='notice'><a href='/news/bridge'><p>#{passage.strip}</p></a><p><a href='/news/bridge'>Weiterlesen</a></p></div>" \
           "<div class='notice'><a href='/news/ferry'><p>The ferry runs late on Sunday.</p></a><p><a href='/news/ferry'>Weiterlesen</a></p></div>"
    text_after(html).should == "#{passage.strip}WeiterlesenThe ferry runs late on Sunday."
  end

  it "reads a link around many levels of blocks in time linear in its text" do
    body = "<p>The bridge over the inner basin opens again on Monday after three months of repairs.</p>" * 10_000
    html = "<div><a href='/news/bridge'>#{'<div>' * 200}<p>The harbor bridge reopens</p>#{body}#{'</div>' * 200}</a>" \
           "<p><a href='/news/bridge'>Read more</a></p></div>"
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    text = text_after(html)

    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).should < 1
    text.should end_with("Read more")
  end

  it "keeps a name that goes on from the title's link, but not a label after a sentence or a line break" do
    html = "<div><a href='/posts/12'>Philosophy of life: a life shaped by curiosity </a>" \
           "<span><a href='/posts/12'><b>- Vijay Joshi</b></a><span></span></span></div>" \
           "<div><a href='/posts/9'>The harbor bridge reopens!</a><span><a href='/posts/9'>Details</a></span></div>" \
           "<div><a href='/posts/7'>Crews finish early</a><br><span><a href='/posts/7'>Details</a></span></div>" \
           "<div><a href='/posts/5'>Ferry times change<br></a><span><a href='/posts/5'>Details</a></span></div>"
    text_after(html).should == "Philosophy of life: a life shaped by curiosity - Vijay JoshiThe harbor bridge reopens!" \
                               "Crews finish earlyFerry times change"
  end

  it "keeps the entries of a breadcrumb or a table of contents" do
    html = "<nav><a href='/guide/intro'>A quick guide to building apps</a><ol><li><a href='/guide/intro'>Intro</a></li>" \
           "<li><a href='/guide/setup'>Setup</a></li><li><a href='/guide/basics'>Basics</a></li></ol></nav>"
    text_after(html).should == "A quick guide to building appsIntroSetupBasics"
  end

  it "keeps a source's domain and a dataset's format after the title" do
    html = card("The harbor bridge reopens", "<p><a href='/posts/25'>vice.com</a></p>") +
           card("Crews finish early", "<ul><li><a href='/posts/18' data-format='csv'>CSV</a></li></ul>")
    text_after(html).should == "The harbor bridge reopensA short excerpt of the post…vice.com" \
                               "Crews finish earlyA short excerpt of the post…CSV"
  end

  it "keeps a name placed like the longer name before it" do
    html = "<table><tr><td><b><a href='/fam/9'>Francis Coleman Allen</a></b></td><td><b><a href='/fam/7'>Shepard Trenholm</a></b></td></tr>" \
           "<tr><td><b><a href='/fam/9'>Minnie Black</a></b></td><td><b><a href='/fam/7'>Henrietta Polley</a></b></td></tr></table>"
    text_after(html).should == "Francis Coleman AllenShepard TrenholmMinnie BlackHenrietta Polley"
  end

  it "keeps a name over a line of its own" do
    html = "<div><p><a href='/fam/7'>Shepard Steven Trenholm</a></p><p><b><a href='/fam/7'>Henrietta Polley</a></b><br>(1862 - 1927)</p></div>"
    text_after(html).should == "Shepard Steven TrenholmHenrietta Polley(1862 - 1927)"
  end

  it "removes the label but not an image or a video beside it" do
    root = prune(card("The harbor bridge reopens", "<div><iframe src='https://www.youtube.com/embed/abc'></iframe><a href='/posts/25'>Leer más</a></div>") +
                 card("Crews finish early", "<div><a href='/posts/18'><img src='/18.jpg'></a><a href='/posts/18'>Leer más</a></div>"))
    root.css("iframe, img").size.should == 2
    Nokodown::Dom.text(root).should_not include("Leer más")
  end

  it "keeps links a colon or a breadcrumb leads into and links to another part of the page" do
    html = card("The harbor bridge reopens", "<p>Filed under: <a href='/posts/25'>Bridge</a></p><p><a href='/'>Home</a> › <a href='/posts/25'>Bridge</a></p>") +
           "<article><h2><a href='/guide#setup'>Setting up the stove</a></h2><p><a href='/guide#use'>Use</a></p></article>"
    text_after(html).should end_with("Filed under: BridgeHome › BridgeSetting up the stoveUse")
  end

  it "keeps download links, menu items over a submenu and the cells of a data table" do
    html = "<article><h2><a href='/report.pdf'>Annual report for the year</a></h2><p><a href='/report.pdf'>Open</a></p></article>" \
           "<nav><h2><a href='/shop'>Shop everything we sell</a></h2><ul><li><a href='/shop'>Shop</a><ul><li><a href='/s/1'>Stoves</a></li></ul></li></ul></nav>" \
           "<table><tr><th>Stove</th><th>Shop</th></tr><tr><td><b><a href='/s/1'>Trail Stove Two Burner</a></b></td><td><a href='/s/1'>Buy</a></td></tr></table>"
    text_after(html).should == "Annual report for the yearOpenShop everything we sellShopStovesStoveShopTrail Stove Two BurnerBuy"
  end
end

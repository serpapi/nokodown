# frozen_string_literal: true

RSpec.describe Nokodown::RepeatedLinks do
  def text_after(html)
    root = Nokolexbor::HTML("<body><div class='list'>#{html}</div></body>").at_css("div.list")
    Nokodown::Dom.assign_keys(root)
    described_class.new(root).call
    Nokodown::Dom.text(root)
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
           "<div><a href='/game/2'><div>15 September, 19:00</div></a><div><a href='/game/2'>Bunker</a></div></div>"
    text_after(html).should == "Episode 54 addedPokémon15 September, 19:00Bunker"
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
end

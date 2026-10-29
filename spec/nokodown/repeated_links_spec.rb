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

  it "keeps a short link when the longer link to its page is in another card" do
    html = card("The harbor bridge reopens", "") + "<article><p>#{'Ferry times change. ' * 90}</p></article>" \
                                                   "<p><a href='/posts/25'>Read more</a></p>"
    text_after(html).should end_with("Read more")
  end
end

# frozen_string_literal: true

RSpec.describe Nokodown::Teasers do
  def markdown(html, url, type: nil)
    head = type ? "<head><meta property='og:type' content='#{type}'></head>" : ""
    Nokodown.to_markdown("<html>#{head}<body>#{html}</body></html>", url: url)
  end

  # Keys of the blocks found, before any content is located.
  def blocks(html, url, type = :article)
    body = Nokolexbor::HTML("<html><body>#{html}</body></html>").at_css("body")
    Nokodown::Dom.assign_keys(body)
    described_class.new(body, url, Nokodown::UrlResolver.new(url), type).call
  end

  def story(count)
    sentence = "The harbor bridge reopened on Tuesday after crews replaced the cracked bearings, three weeks after the closure. "
    Array.new(count) { |index| "<p>#{sentence * 2}Part #{index + 1}.</p>" }.join
  end

  # A product page whose details and description share the text, so it is
  # kept as a page rather than narrowed to an article.
  def product(extra)
    rows = { "Weight" => "280 g", "Drop" => "6 mm", "Upper" => "Recycled mesh that drains fast" }
    table = rows.map { |name, value| "<tr><td>#{name}</td><td>#{value}</td></tr>" }.join
    "<div class='info'><h1>Cirrus trail shoe</h1><table>#{table}</table></div>" \
      "<div class='description'><p>A light trail shoe with a rock plate and a wide toe box, made for long days on " \
      "rough ground. It keeps its grip on wet rock and roots, and the foam stays soft on long descents.</p></div>#{extra}"
  end

  def cards(titles, path, excerpt = "")
    titles.map do |title|
      slug = title.downcase.delete("^a-z ").tr(" ", "-")
      "<div class='card'><img src='/img/#{slug}.jpg' alt=''><h3><a href='#{path}#{slug}'>#{title}</a></h3>" \
        "<span>12.04.2026</span>#{excerpt}</div>"
    end.join
  end

  let(:stories) do
    ["School board approves the budget for next year", "Fishing season opens two weeks early this spring",
     "Library extends its opening hours on weekends"]
  end

  let(:box) { "<section><h2>Leia também</h2><div class='grid'>#{cards(stories, '/blog/')}</div></section>" }

  it "finds a titled block of teasers beside the content of an article, whatever the title's language" do
    blocks("<h1>Bridge reopens</h1>#{story(3)}#{box}", "https://news.example.com/2026/05/bridge-reopens").should_not be_empty
  end

  it "keeps titled teasers on a page that declares no article or product" do
    blocks("<h1>Bridge reopens</h1>#{story(3)}#{box}", "https://news.example.com/2026/05/bridge-reopens", nil).should be_empty
  end

  it "keeps teasers for pages below this one" do
    grid = "<section><h2>Our services</h2><div class='grid'>#{cards(stories, '/services/security/')}</div></section>"

    blocks("<h1>Security</h1>#{story(4)}#{grid}", "https://example.com/services/security").should be_empty
  end

  it "removes teasers for pages like this one even when they outweigh its text" do
    products = Array.new(8) do |index|
      "<li class='item'><a href='/shoes/trail-#{index}'><img src='/img/#{index}.jpg' alt=''>" \
        "<h3>Trail shoe model #{index}</h3><span>$129.00 in stock</span></a></li>"
    end.join
    html = product("<div class='also'><h2>Похожие товары</h2><ul class='items'>#{products}</ul></div>")

    text = markdown(html, "https://shop.example.com/shoes/cirrus")
    text.should include("rock plate")
    text.should_not include("Trail shoe model 3")
  end

  it "removes pages like this one listed under its text in the same container" do
    items = stories.each_with_index.map do |title, index|
      "<div class='row'><img src='/img/#{index}.jpg' alt=''><b>12.08.2026</b> <a href='/?n=#{index + 21}&amp;p=1'>#{title}</a> " \
        "<span>A short summary.</span></div>"
    end.join
    rows = { "Date" => "28 August", "Place" => "North pier", "Contact" => "Harbor office, north building, second floor",
             "Hours" => "Every day from six in the morning to ten at night", "Tickets" => "Sold at the pier and on board" }
    table = rows.map { |name, value| "<tr><td>#{name}</td><td>#{value}</td></tr>" }.join
    html = "<div class='info'><h1>Port reopens</h1><table>#{table}</table></div>" \
           "<div class='news'><p>The north pier reopened to ferries on Thursday after the repairs to its mooring posts. " \
           "Crews worked through the night to finish two days early, and the first ferry left on time at six. The harbor " \
           "office expects the south pier to follow next month, once its new fenders arrive.</p>#{items}</div>"

    text = markdown(html, "https://news.example.com/?n=20&p=1")
    text.should include("north pier reopened")
    text.should_not include("School board")
  end

  it "keeps a listing's own list and removes the titled box beside it" do
    popular = ["Snow closes the pass", "Port strike ends", "Ferry fares rise"]
    posts = cards(stories + ["Ferry adds a night crossing"], "/2026/04/", "<p>What changes, and for whom.</p>")
    html = "<h1>Tag: harbor</h1><div class='posts'>#{posts}</div>" \
           "<div class='box'><div class='box-title'>Mest läst</div><div class='grid'>#{cards(popular, '/2026/03/')}</div></div>"

    text = markdown(html, "https://news.example.com/tag/harbor", type: "article")
    text.should include("School board")
    text.should include("Ferry adds a night crossing")
    text.should_not include("Mest läst")
    text.should_not include("Port strike ends")
  end

  it "keeps the titled sections of a hub, however long its intro" do
    sections = %w[Audio Cameras Laptops].map do |name|
      "<section class='shelf'><h2>#{name}</h2><div class='grid'>#{cards(stories.map { |title| "#{name} #{title}" }, '/reviews/')}</div></section>"
    end.join

    blocks("<h1>Electronics</h1>#{story(4)}#{sections}", "https://reviews.example.com/electronics").should be_empty
  end

  it "keeps titled teasers on a page with no text of its own" do
    html = "<h1>Volume 5, issue 2</h1><h2>Articles</h2><div class='grid'>#{cards(stories, '/article/view/')}</div>"

    markdown(html, "https://journal.example.com/issue/view/238", type: "article").should include("School board")
  end

  it "keeps the teasers when the page would be left with a heading and a line" do
    products = Array.new(4) do |index|
      "<div class='tile'><a href='/en-us/mower-#{index}'><img src='/img/#{index}.jpg' alt=''><h3>Robotic mower #{index}</h3></a>" \
        "<p>Cuts up to #{index + 1} acres a day</p></div>"
    end.join
    html = "<h1>Robotic lawn mowers</h1><p>Quiet mowers for any lawn, without a boundary wire.</p>" \
           "<section><h2>Models</h2><div class='tiles'>#{products}</div></section>"

    markdown(html, "https://www.example.com/en-us/robotic-lawn-mowers").should include("Robotic mower 2")
  end

  it "keeps a list of links in the prose" do
    items = stories.map { |title| "<li><a href='/docs/#{title.length}'>#{title}</a> explains the next step in detail.</li>" }
    html = product("<h2>What's next</h2><ul>#{items.join}</ul>")

    markdown(html, "https://shop.example.com/shoes/cirrus", type: "product").should include("School board")
  end

  it "finds no teaser blocks on a site's home page" do
    html = "<h1>Harbor News</h1>#{story(4)}<section><h2>Latest</h2><div class='grid'>#{cards(stories, '/2026/04/')}</div></section>"

    blocks(html, "https://news.example.com/2026/05/bridge-reopens").should_not be_empty
    blocks(html, "https://news.example.com/en/").should be_empty
  end
end

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
    sentence = "The harbor bridge reopened on Tuesday after crews replaced the cracked bearings. "
    Array.new(count) { |index| "<p>#{sentence * 3}Part #{index + 1}.</p>" }.join
  end

  # A product page whose details and description share the text, so it is
  # kept as a page rather than narrowed to an article.
  def product(extra)
    rows = { "Weight" => "280 g", "Drop" => "6 mm", "Upper" => "Recycled mesh that drains fast" }
    table = rows.map { |name, value| "<tr><td>#{name}</td><td>#{value}</td></tr>" }.join
    "<div class='info'><h1>Cirrus trail shoe</h1><table>#{table}</table></div><div class='description'>" \
      "<p>A light trail shoe with a rock plate and a wide toe box, made for long days on rough ground. It keeps " \
      "its grip on wet rock and roots, and the foam stays soft on long descents.</p></div>#{extra}"
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

  let(:article) do
    "<h1>Bridge reopens</h1>#{story(3)}" \
      "<section><h2>Leia também</h2><div class='grid'>#{cards(stories, '/blog/')}</div></section>"
  end
  let(:article_url) { "https://news.example.com/2026/05/bridge-reopens" }

  it "finds a titled block of teasers beside the content of an article, whatever the title's language" do
    blocks(article, article_url).should_not be_empty
  end

  it "drops the heading left over the blocks it removes" do
    columns = %w[Ferries Port].map { |name| "<div class='col'><h4>#{name}</h4>#{cards(stories, '/blog/')}</div>" }
    html = "<div class='story'>#{story(1)}<section><h2>Previous matches</h2>#{columns.join}</section></div>"
    root = Nokolexbor::HTML("<html><body>#{html}</body></html>").at_css(".story")
    Nokodown::Dom.assign_keys(root)

    described_class.strip([root], root.css(".col").map { |column| Nokodown::Dom.key(column) }.to_set)
    root.content.should include("cracked bearings")
    root.content.should_not include("Previous matches")
  end

  it "never drops the page's main element" do
    grid = "<div class='grid'>#{cards(stories, '/blog/')}</div>"
    html = "<div class='story'>#{story(3)}</div><main><h2>Leia também</h2>#{grid}</main>"
    body = Nokolexbor::HTML("<html><body>#{html}</body></html>").at_css("body")
    Nokodown::Dom.assign_keys(body)
    url = article_url

    keys = described_class.new(body, url, Nokodown::UrlResolver.new(url), :article).call
    keys.should_not include(Nokodown::Dom.key(body.at_css("main")))
  end

  it "keeps a titled box that holds a large share of the page" do
    titles = stories + ["Port strike ends", "Ferry fares rise", "Snow closes the pass"]
    box = "<section><h2>Leia também</h2>#{cards(titles, '/blog/', '<p>Read on to see what changes.</p>')}</section>"
    html = "<h1>Bridge reopens</h1>#{story(2)}#{box}"

    blocks(html, article_url).should be_empty
  end

  it "keeps the rows of a data table" do
    rows = stories.map do |title|
      slug = title.downcase.delete("^a-z ").tr(" ", "-")
      "<tr><td><a href='/blog/#{slug}'>#{title}</a></td><td>12.04.2026</td><td>51 KB</td></tr>"
    end
    header = "<thead><tr><td>Name</td><td>Uploaded</td><td>Size</td></tr></thead>"
    html = "<h1>Bridge reopens</h1>#{story(3)}<h2>Earlier versions</h2><table>#{header}<tbody>#{rows.join}</tbody></table>"

    blocks(html, article_url).should be_empty
  end

  it "does not take the label of a sort control for the title of a list" do
    sort = "<div class='sort'><span>Sort by:</span><form><select name='sort'><option>Price</option></select></form></div>"
    html = "<h1>Bridge reopens</h1>#{story(3)}<div>#{sort}<div class='grid'>#{cards(stories, '/shop/')}</div></div>"

    blocks(html, article_url).should be_empty
  end

  it "does not take a count over a list of cards for its title" do
    grid = "<div class='grid'>#{cards(stories, '/blog/')}</div>"
    html = "<h1>Bridge reopens</h1>#{story(3)}<p>Showing 1-3 of 40</p>#{grid}"

    blocks(html, article_url).should be_empty
  end

  it "keeps a forum's list of threads, which the same script shows under other query keys" do
    threads = stories.each_with_index.map do |title, index|
      "<div class='row'><img src='/icons/topic.gif' alt=''><a href='index.php?topic=#{70 + index}.0'>#{title}</a>" \
        "<span>by wren, 12.04.2026</span></div>"
    end.join
    html = "<div class='board'>#{story(1)}#{threads}</div>"

    blocks(html, "https://forum.example.com/index.php?board=2.0", :forum).should be_empty
  end

  it "keeps titled teasers on a page that declares no article or product" do
    blocks(article, article_url, nil).should be_empty
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

  it "keeps a listing whose address looks like its items' when its list comes first" do
    products = Array.new(6) do |index|
      "<li class='item'><a href='/san-pham/tra-sam-#{index}'><img src='/img/#{index}.jpg' alt=''>" \
        "<h3>Trà sâm số #{index}</h3><span>1.400.000 đ, còn hàng</span></a></li>"
    end.join
    html = "<div class='cat'><h2>Trà sâm</h2><ul class='items'>#{products}</ul></div>" \
           "<p>Giao hàng toàn quốc trong ba ngày, đổi trả miễn phí trong bảy ngày.</p>"

    blocks(html, "https://shop.example.com/san-pham/tra-sam-27", :product).should be_empty
  end

  it "removes pages like this one listed under its text in the same container" do
    items = stories.each_with_index.map do |title, index|
      "<div class='row'><img src='/img/#{index}.jpg' alt=''><b>12.08.2026</b> " \
        "<a href='/?n=#{index + 21}&amp;p=1'>#{title}</a> <span>A short summary.</span></div>"
    end.join
    rows = {
      "Date" => "28 August", "Place" => "North pier", "Contact" => "Harbor office, north building, second floor",
      "Hours" => "Every day from six in the morning to ten at night", "Tickets" => "Sold at the pier and on board"
    }
    table = rows.map { |name, value| "<tr><td>#{name}</td><td>#{value}</td></tr>" }.join
    html = "<div class='info'><h1>Port reopens</h1><table>#{table}</table></div>" \
           "<div class='news'><p>The north pier reopened to ferries on Thursday after the repairs to its mooring " \
           "posts. Crews worked through the night to finish two days early, and the first ferry left on time at " \
           "six. The harbor office expects the south pier to follow next month, once its new fenders arrive.</p>" \
           "#{items}</div>"

    text = markdown(html, "https://news.example.com/?n=20&p=1")
    text.should include("north pier reopened")
    text.should_not include("School board")
  end

  it "keeps a listing's own list and removes the titled box beside it" do
    popular = ["Snow closes the pass", "Port strike ends", "Ferry fares rise"]
    posts = cards(stories + ["Ferry adds a night crossing"], "/2026/04/", "<p>What changes, and for whom.</p>")
    html = "<h1>Tag: harbor</h1><div class='posts'>#{posts}</div><div class='box'>" \
           "<div class='box-title'>Mest läst</div><div class='grid'>#{cards(popular, '/2026/03/')}</div></div>"

    text = markdown(html, "https://news.example.com/tag/harbor", type: "article")
    text.should include("School board")
    text.should include("Ferry adds a night crossing")
    text.should_not include("Mest läst")
    text.should_not include("Port strike ends")
  end

  it "keeps the titled sections of a hub, however long its intro" do
    sections = %w[Audio Cameras Laptops].map do |name|
      grid = cards(stories.map { |title| "#{name} #{title}" }, "/reviews/")
      "<section class='shelf'><h2>#{name}</h2><div class='grid'>#{grid}</div></section>"
    end.join

    blocks("<h1>Electronics</h1>#{story(4)}#{sections}", "https://reviews.example.com/electronics").should be_empty
  end

  it "keeps titled teasers on a page with no text of its own" do
    html = "<h1>Volume 5, issue 2</h1><h2>Articles</h2><div class='grid'>#{cards(stories, '/article/view/')}</div>"

    markdown(html, "https://journal.example.com/issue/view/238", type: "article").should include("School board")
  end

  it "keeps the teasers when the page would be left with a heading and a line" do
    products = Array.new(4) do |index|
      "<div class='tile'><a href='/en-us/mower-#{index}'><img src='/img/#{index}.jpg' alt=''>" \
        "<h3>Robotic mower #{index}</h3></a><p>Cuts up to #{index + 1} acres a day</p></div>"
    end.join
    html = "<h1>Robotic lawn mowers</h1><p>Quiet mowers for any lawn, without a boundary wire.</p>" \
           "<section><h2>Models</h2><div class='tiles'>#{products}</div></section>"

    markdown(html, "https://www.example.com/en-us/robotic-lawn-mowers").should include("Robotic mower 2")
  end

  it "drops the threads listed below a thread and keeps every post, with its attribution" do
    replies = {
      "wren" => "My starter smells like nail polish remover after two days in the fridge. Is it ruined, or hungry?",
      "basil" => "Just hungry. The acetone smell means the yeast ran out of food, so feed it twice in the warmth.",
      "sage" => "Agreed with basil. Keep it on the counter and it will smell sweet and yeasty again within a day."
    }
    posts = replies.map do |name, text|
      "<div class='post'><div class='meta'><span class='username'>#{name}</span> " \
        "<time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time> <span>via the mobile app</span> " \
        "<span>edited twice today</span> <span>one more label here</span></div>" \
        "<div class='content'><p>#{text}</p></div></div>"
    end
    threads = ["Starter not rising after a week", "Best flour for a rye starter", "How often to feed a starter"]
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
           "<h1>Starter smells like acetone</h1><div class='posts'>#{posts.join}</div>" \
           "<section><h2>Similar threads</h2><div class='grid'>#{cards(threads, '/threads/')}</div></section>" \
           "</main></body></html>"

    text = Nokodown.to_markdown(html, url: "https://forum.example.com/threads/starter")
    text.should include("**sage** · May 3, 2024")
    text.should include("smell sweet and yeasty")
    text.should_not include("Best flour for a rye starter")
  end

  it "keeps the attachments of a post" do
    files = %w[wiring-front wiring-back drive-label].each_with_index.map do |name, index|
      "<li class='file'><a href='/attachments/#{name}.#{180 + index}/'><img src='/data/#{name}.jpg' alt=''></a>" \
        "<span>#{name}.jpeg</span><span>3.1 MB, viewed 32 times</span></li>"
    end.join
    post = "<div class='post'><div class='meta'><span class='username'>stover</span> " \
           "<time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time></div><div class='content'>#{story(1)}" \
           "<section><h4>Attachments</h4><ul>#{files}</ul></section></div></div>"
    html = "<html><body><h1>Wiring the drive</h1><div class='posts'>#{post * 2}</div></body></html>"
    body = Nokolexbor::HTML(html).at_css("body")
    Nokodown::Dom.assign_keys(body)
    Nokodown::PostAttribution.new(body).call.write([body])
    url = "https://forum.example.com/threads/wiring.1724/"

    described_class.new(body, url, Nokodown::UrlResolver.new(url), :forum).call.should be_empty
  end

  it "keeps the posts of a thread whose titles link to the posts themselves" do
    posts = Array.new(5) do |index|
      id = 657_618 + index
      "<div class='post' id='p#{id}'><h3><a href='./viewtopic.php?p=#{id}#p#{id}'>Re: Door scripts</a></h3>" \
        "<p>Reply #{index}: the script runs once the map loads, so the door opens after the first switch.</p></div>"
    end.join
    html = "<div class='topic'>#{story(1)}#{posts}</div>"

    blocks(html, "https://forum.example.com/viewtopic.php?p=657618", :forum).should be_empty
  end

  it "finds pages like this one that link to an anchor every such page has" do
    items = Array.new(4) do |index|
      "<div class='col'><a href='producto.php?id=#{480 + index}#a'><img src='/img/#{index}.jpg' alt=''></a></div>"
    end.join
    html = "<a name='a'></a><h1>Drain cleaning</h1>#{story(1)}<h3>Other services</h3><div class='row'>#{items}</div>"

    blocks(html, "https://plumber.example.com/producto.php?id=566", nil).should_not be_empty
  end

  it "keeps the records a catalogue lists on a category page" do
    records = Array.new(4) do |index|
      "<div class='record'><img src='/covers/#{index}.jpg' alt=''>" \
        "<a href='index.php?lvl=notice_display&amp;id=#{4100 + index}'>Soil survey, volume #{index + 1}</a>" \
        "<span>Report, 2019</span></div>"
    end.join
    html = "<div class='category'>#{story(1)}#{records}</div>"

    blocks(html, "https://library.example.org/index.php?lvl=categ_see&id=83018", nil).should be_empty
  end

  it "finds no block in the cards spread between the paragraphs of an article" do
    figures = stories.map { |title| "#{cards([title], '/blog/')}#{story(1)}" }
    html = "<h1>Bridge reopens</h1><div class='entry'>#{story(1)}<p>See our earlier report.</p>#{figures.join}</div>"

    blocks(html, article_url).should be_empty
  end

  it "finds one block in a column of widgets, each a title over a card" do
    widgets = stories.map { |title| "<h2>#{title.split.first}</h2>#{cards([title], '/blog/')}" }
    html = "<h1>Bridge reopens</h1>#{story(3)}<div class='column'>#{widgets.join}</div>"

    blocks(html, article_url).should_not be_empty
  end

  it "finds no block in the screenshots under the step headings of an article" do
    steps = Array.new(3) do |index|
      "<h2>Step #{index + 1}</h2><figure><a href='/2026/05/bridge-reopens-0#{index + 1}/'>" \
        "<img src='/img/step-#{index}.png' alt=''></a></figure>"
    end
    html = "<h1>Bridge reopens</h1><div class='entry'>#{story(2)}#{steps.join}</div>"

    blocks(html, article_url).should be_empty
  end

  it "does not take a sentence before a list of cards for its title" do
    grid = "<div class='grid'>#{cards(stories, '/blog/')}</div>"
    html = "<h1>Bridge reopens</h1>#{story(3)}<p>See our earlier report.</p>#{grid}"

    markdown(html, article_url, type: "article").should include("See our earlier report.")
  end

  it "keeps a list of links in the prose" do
    items = stories.map { |title| "<li><a href='/docs/#{title.length}'>#{title}</a> explains the next step.</li>" }

    blocks("<h1>Getting started</h1>#{story(4)}<h2>What's next</h2><ul>#{items.join}</ul>", article_url).should be_empty
  end

  it "finds no teaser blocks on a site's home page" do
    blocks(article, article_url).should_not be_empty
    blocks(article, "https://news.example.com/en/").should be_empty
  end
end

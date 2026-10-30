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

  # Not wall time, which a loaded machine stretches.
  def cpu_time
    Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
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

  # A listing under its column's title, after a sidebar, with its pager.
  def listing(pages)
    products = Array.new(6) do |index|
      "<li><span><a href='/products/show2846#{660 + index}.html'><img src='/img/#{index}.png' alt=''></a></span>" \
        "<a href='/products/show2846#{660 + index}.html'>Methyl ester number #{index}</a></li>"
    end.join
    links = pages.map { |text, href| "<a href='#{href}'>#{text}</a>" }.join
    "<div class='side'><span>Contact us</span><ul><li>Contact: Li Fang</li><li>Phone: 139 8604 1085</li>" \
      "<li>Address: group one, Ximiao village, Huangtan</li></ul></div><div class='main'><div class='head'>" \
      "<span>Product showroom</span></div><ul class='list'>#{products}</ul><div class='pages'>#{links}</div></div>"
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
    html = "<h1>Bridge reopens</h1>#{story(3)}<section><h2>Harbor</h2><div class='grid'>#{cards(stories, '/blog/')}</div></section>"

    blocks(html, article_url, nil).should be_empty
  end

  it "removes teasers under a title that calls them related on any page" do
    blocks(article, article_url, nil).should_not be_empty
  end

  it "takes a Turkish title in title case for one that calls teasers related" do
    html = "<h1>Bridge reopens</h1>#{story(3)}<section><h2>Bunlar da İlginizi Çekebilir</h2>" \
           "<div class='grid'>#{cards(stories, '/blog/')}</div></section>"

    blocks(html, article_url, nil).should_not be_empty
  end

  it "does not take a title that names questions for one that calls teasers related" do
    html = "<h1>Bridge reopens</h1>#{story(3)}<section><h2>Популярные вопросы</h2>" \
           "<div class='grid'>#{cards(stories, '/blog/')}</div></section>"

    blocks(html, article_url, nil).should be_empty
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

  it "takes dated permalinks and coded product pages for pages like this one" do
    rows = lambda do |href|
      stories.each_with_index.map do |title, index|
        "<div class='row'><b>12.08.2026</b> <a href='#{href.call(index)}'>#{title}</a> <span>A short summary.</span></div>"
      end.join
    end
    dated = rows.call(->(index) { "/2026/4/#{index + 2}/port/#{575_500 + index}.html" })
    coded = rows.call(->(index) { "/fq0#{index}4100.html" })

    blocks("<div class='news'>#{story(2)}#{dated}</div>", "https://news.example.com/2026/4/30/port/575431.html").should_not be_empty
    blocks("<div class='news'>#{story(2)}#{coded}</div>", "https://shop.example.com/fq146100.html").should_not be_empty
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

  it "keeps a listing whose column title and pager sit around its list, after a sidebar" do
    pages = [["&lt; Prev", 2], ["1", 1], ["2", 2], ["3", 3], ["4", 4], ["Next &gt;", 4]].map do |text, page|
      [text, "/products/list-catid-139257_--p#{page}.html"]
    end

    blocks(listing(pages), "https://chem.example.com/products/list-catid-139257_--p3.html", nil).should be_empty
  end

  it "keeps a listing whose pager adds the page's number to its address" do
    pages = [["1", ""], ["2", "?page=2"], ["3", "?page=3"], ["4", "?page=4"], ["Next &gt;", "?page=2"]]
    pages = pages.map { |text, query| [text, "/products/list-catid-139257.html#{query}"] }

    blocks(listing(pages), "https://chem.example.com/products/list-catid-139257.html", nil).should be_empty
  end

  it "does not take the view counts of coded pages for a pager" do
    videos = Array.new(6) do |index|
      "<div class='item'><a href='/9331#{index}.html'><img src='/img/#{index}.jpg' alt=''></a>" \
        "<a href='/9331#{index}.html'>#{450 + index}</a> <span>09-21</span>" \
        "<h3><a href='/9331#{index}.html'>Harbor video number #{index}</a></h3></div>"
    end.join
    html = "<h1>Harbor video</h1>#{story(1)}<div class='box'><div class='title'>You may also like</div>" \
           "<div class='grid'>#{videos}</div></div>"

    blocks(html, "https://video.example.com/85967.html").should_not be_empty
  end

  it "does not take links that change two of this page's numbers for its pager" do
    volumes = [[1, 1], [3, 27], [4, 40], [5, 52]].map do |volume, chapter|
      href = "/read/harbor/vol-#{volume}/ch-#{chapter}.html"
      "<div class='volume'><a href='#{href}'><img src='/img/#{volume}.jpg' alt=''></a>" \
        "<a href='#{href}'>#{volume}</a></div>"
    end.join
    html = "<h1>Harbor, chapter 14</h1>#{story(2)}<div class='box'><h3>More volumes</h3>#{volumes}</div>"

    blocks(html, "https://manga.example.com/read/harbor/vol-2/ch-14.html").should_not be_empty
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

  it "keeps a block in a section that the page's table of contents lists" do
    rows = %w[ranger scholar sage soldier].map do |order|
      "<a href='/db/item/boots_#{order}'><img src='/icons/boots_#{order}.webp' alt=''>" \
        "<div>Shadow boots of the #{order} order</div><div>III</div><div>0</div></a>"
    end.join
    header = "<div><div>Name</div><button>Tier</button><button>Level</button></div>"
    toc = "<nav><ul><li><a href='#about'>About</a></li><li><a href='#recipes'>Recipes</a></li>" \
          "<li><a href='#pictures'>Pictures</a></li></ul></nav>"
    html = "<h1>Watcher boots</h1><p>Heavy boots of gear score 350, tier three, bound on pickup. They drop from " \
           "the watchers in the eastern ruins and are crafted at an outfitting station.</p>#{toc}" \
           "<section id='about'><h2>About</h2><p>Bound on pickup.</p></section>" \
           "<section id='recipes'><h2>Used in recipes</h2><div>#{header}<div>#{rows}</div></div></section>" \
           "<section id='pictures'><h2>Pictures</h2><p>No pictures yet.</p></section>"
    url = "https://db.example.net/db/item/boots_watcher"

    markdown(html, url).should include("[Shadow boots of the sage order](https://db.example.net/db/item/boots_sage)")
    markdown(html.sub(toc, ""), url).should_not include("Shadow boots of the sage order")
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

  it "takes an empty link that opens a card for the link of its title" do
    overlaid = stories.map do |title|
      slug = title.downcase.delete("^a-z ").tr(" ", "-")
      "<div class='card'><a href='/blog/#{slug}'></a><img src='/img/#{slug}.jpg' alt=''><h3>#{title}</h3></div>"
    end
    html = "<h1>Bridge reopens</h1>#{story(3)}<section><h2>Leia também</h2><div class='grid'>#{overlaid.join}</div></section>"

    blocks(html, article_url).should_not be_empty
  end

  it "does not take an empty link deep in a card for one stretched over it" do
    services = %w[Architecture Decoration Joinery].map do |name|
      "<div class='col'><h3>#{name}</h3><div class='image'><div class='hover'><a href='/#{name.downcase}-services/'>" \
        "</a></div></div><p>We plan the #{name.downcase} of your home in every detail and keep to the budget.</p></div>"
    end
    html = "<h1>Interior architect</h1>#{story(3)}<h2>Our services</h2><div class='row'>#{services.join}</div>"

    blocks(html, "https://studio.example.com/interior-architect/").should be_empty
  end

  it "takes a card's title link over an empty link that shows its thumbnail" do
    news = stories.each_with_index.map do |title, index|
      "<div class='news'><a href='/news/#{index}' style='background:url(/img/#{index}.jpg)'></a>" \
        "<a href='/news/#{index}'>#{title}</a><span>12.04.2026</span></div>"
    end
    html = "<h1>Bridge reopens</h1>#{story(3)}<div class='more'><h3>On this topic</h3>#{news.join}</div>"

    blocks(html, "https://news.example.com/news/9").should_not be_empty
  end

  it "weighs each titled box, not all of them together, against the page's own text" do
    boxes = %w[popular latest picks].map do |name|
      "<div class='#{name}'><h3>#{name.capitalize}</h3>" \
        "#{cards(stories.map { |title| "#{name.capitalize}: #{title}" }, '/blog/', '<p>What changes, and for whom.</p>')}</div>"
    end
    html = "<h1>Bridge reopens</h1>#{story(2)}#{boxes.join}"

    blocks(html, article_url).size.should == 6
  end

  it "keeps a category's products that sit in a folder of their own" do
    products = Array.new(4) do |index|
      "<li class='item'><a href='/fr-fr/gate-feeders/gfh0#{index}'><img src='/img/#{index}.jpg' alt=''>" \
        "<h3>Hay feeder GFH0#{index}</h3><span>Item number GFH0#{index}</span></a></li>"
    end
    html = "<h1>Calf hay feeders</h1><p>Feeders that keep hay off the ground and dry for calves.</p>" \
           "<div class='sort'>Sort by:</div><ul class='items'>#{products.join}</ul>"

    blocks(html, "https://store.example.com/fr-fr/calf-hay-feeders/", nil).should be_empty
  end

  it "takes posts named by their titles under the root for pages like this one under a heading" do
    html = "<h1>Bridge reopens</h1>#{story(1)}<section><h2>Beach days</h2>" \
           "<div class='grid'>#{cards(stories, '/')}</div></section>"

    blocks(html, "https://blog.example.com/bridge-reopens-after-repairs/", nil).should_not be_empty
  end

  it "takes a list of posts named by their titles under the root for pages like this one below an article" do
    links = stories.map { |title| "<li><a href='/#{title.downcase.tr(' ', '-')}/'>#{title}</a></li>" }
    html = "<h1>Bridge reopens</h1>#{story(1)}<div class='label'>Beach days</div><ul>#{links.join}</ul>"

    blocks(html, "https://blog.example.com/bridge-reopens-after-repairs/").should_not be_empty
  end

  it "keeps a shop's products named by their titles under a label of the page's own" do
    html = "<h1>Olive oil tin cans</h1><p>Tin cans for olive oil.</p><div class='name'>All olive oil cans</div>" \
           "<div class='grid'>#{cards(stories, '/')}</div>"

    blocks(html, "https://cans.example.com/supplier-4760341-olive-oil-tin-cans", :product).should be_empty
  end

  it "removes a titled list of bare links to pages like this one" do
    titles = ["Another simple idea for sewing trousers", "A great idea for decorating at home",
              "Sewing a bag from leftover fabric"]
    items = titles.each_with_index.map { |title, index| "<li><a href='/posts/#{4436 + index}-idea.html'>#{title}</a></li>" }
    html = "<h1>A simple idea for sewing women's trousers</h1><p>By lesorub, two months ago, liked 508 times.</p>" \
           "<p>Cut the front and back from one piece of linen, then sew the side seams and turn the waistband over " \
           "an elastic band.</p><h3>Смотрите также</h3><ul>#{items.join}</ul>"

    blocks(html, "https://crafts.example.com/posts/8449-idea.html", nil).should_not be_empty
  end

  it "keeps a list of bare links that holds most of the page" do
    titles = ["Field survey of wetland birds", "Flood maps for the river basin", "Forest cover change since 1990",
              "Fishing permits by district", "Fuel stations along the coast"]
    items = titles.each_with_index.map { |title, index| "<li><a href='/wiki/Map_#{index}'>#{title}</a></li>" }
    html = "<h1>Category: Maps</h1><p>The following 5 pages are in this category, out of 5 total.</p>" \
           "<h2>Pages in this category</h2><ul>#{items.join}</ul>"

    blocks(html, "https://maps.example.org/wiki/Category_Maps").should be_empty
  end

  it "keeps a list under a letter of an index" do
    titles = ["Water quality of the lakes", "Weather stations of the region", "Wind farms planned until 2030"]
    items = titles.each_with_index.map { |title, index| "<li><a href='/wiki/Map_#{index}'>#{title}</a></li>" }
    html = "<h1>Category: Maps</h1>#{story(2)}<div class='group'><h3>W</h3><ul>#{items.join}</ul></div>"

    blocks(html, "https://maps.example.org/wiki/Category_Maps").should be_empty
  end

  it "keeps the sections of a site map" do
    sections = { "Release notes" => "", "Virtual hosts" => "vhosts/", "Rewriting addresses" => "rewrite/" }.map do |title, folder|
      links = ["Upgrading from the last version", "New features of this release", "Compiling and installing"]
      items = links.each_with_index.map { |link, index| "<li><a href='/docs/#{folder}page#{index}.html'>#{link}</a></li>" }
      "<div class='section'><h2>#{title}</h2><ul>#{items.join}</ul></div>"
    end
    html = "<h1>Site map</h1><p>This page lists every document of the manual, grouped by subject.</p>#{sections.join}"

    blocks(html, "https://docs.example.org/docs/sitemap.html", nil).should be_empty
  end

  it "does not take a list of bare links beside two boxes of cards for a hub's section" do
    boxes = %w[Picks Highlights].map do |name|
      "<div class='box #{name.downcase}'><h3>#{name}</h3>" \
        "#{cards(stories.map { |title| "#{name}: #{title}" }, '/blog/', '<p>What changes, and for whom.</p>')}</div>"
    end
    links = stories.each_with_index.map { |title, index| "<li><a href='/2026/04/read-#{index}'>Read: #{title}</a></li>" }
    html = "<h1>Bridge reopens</h1>#{story(2)}#{boxes.join}<div class='box'><h3>Reading</h3><ul>#{links.join}</ul></div>"
    body = Nokolexbor::HTML("<html><body>#{html}</body></html>").at_css("body")
    Nokodown::Dom.assign_keys(body)

    keys = described_class.new(body, article_url, Nokodown::UrlResolver.new(article_url), :article).call
    keys.should include(Nokodown::Dom.key(body.at_css(".picks")), Nokodown::Dom.key(body.at_css(".highlights")))
  end

  it "weighs Chinese characters as words in the titles of a list of bare links" do
    titles = %w[港口大桥重新开放 学校董事会批准预算 渔季提前两周开放]
    items = titles.each_with_index.map { |title, index| "<li><a href='/news/#{index}.html'>#{title}</a></li>" }
    html = "<h1>大桥重新开放</h1>#{story(2)}<h3>相关文章</h3><ul>#{items.join}</ul>"

    blocks(html, "https://news.example.cn/news/9.html", nil).should_not be_empty
  end

  it "finds teasers whose cards each hold a list of links to pages like this one" do
    grid = stories.each_with_index.map do |title, index|
      topics = ["Harbor bridge news", "Ferry timetable changes", "Road closures this week"].each_with_index.map do |topic, other|
        "<li><a href='/2026/04/topic-#{index}-#{other}'>#{topic}</a></li>"
      end
      "<div class='card'><img src='/img/#{index}.jpg' alt=''><h3><a href='/blog/story-#{index}'>#{title}</a></h3>" \
        "<ul>#{topics.join}</ul></div>"
    end
    html = "<h1>Bridge reopens</h1>#{story(3)}<section><h2>Leia também</h2><div class='grid'>#{grid.join}</div></section>"
    body = Nokolexbor::HTML("<html><body>#{html}</body></html>").at_css("body")
    Nokodown::Dom.assign_keys(body)

    keys = described_class.new(body, article_url, Nokodown::UrlResolver.new(article_url), :article).call
    keys.should include(Nokodown::Dom.key(body.at_css("section")))
  end

  it "keeps a list of short links, such as a product's options" do
    sizes = %w[60x110 80x150 120x170].map { |size| "<li><a href='/p/rug-#{size}'>#{size}</a></li>" }
    html = "<h1>Round rug</h1>#{story(1)}<h4>Diameter (mm)</h4><ul>#{sizes.join}</ul>"

    blocks(html, "https://shop.example.com/p/rug-40x60", :product).should be_empty
  end

  it "keeps links set in a line of text" do
    links = stories.each_with_index.map { |title, index| "<a href='/blog/#{index}'>#{title}</a>" }
    html = "<h1>Bridge reopens</h1>#{story(1)}<h4>Sources</h4><p>Sources: #{links.join(', ')}.</p>"

    blocks(html, "https://news.example.com/blog/9", nil).should be_empty
  end

  it "does not take the first entry of a menu for the title of a list of bare links" do
    entries = ["Opening hours of the shop", "Parking near the shop", "How to reach the shop by train"]
    items = entries.each_with_index.map { |entry, index| "<li class='entry'><a href='/info/#{index}'>#{entry}</a></li>" }
    html = "<h1>Autumn sale</h1>#{story(1)}<ul><li class='home'><a href='/'>Home</a></li>#{items.join}</ul>"

    blocks(html, "https://shop.example.com/info/9", nil).should be_empty
  end

  it "keeps a list under a title that the page's address names" do
    html = "<h1>Bridge reopens</h1>#{story(1)}<section><h2>Harbor bridge news</h2>" \
           "<div class='grid'>#{cards(stories, '/')}</div></section>"

    blocks(html, "https://news.example.com/harbor-bridge-news/", :article).should be_empty
  end

  it "does not take a longer title that uses the address's words for the page's name" do
    box = "<section><h2>Refresh your digital marketing skills</h2><div class='grid'>#{cards(stories, '/courses/')}</div></section>"

    blocks("<h1>What is digital marketing</h1>#{story(3)}#{box}", "https://example.org/what-is-digital-marketing/").should_not be_empty
  end

  it "does not take a title that has the address's words among many others for the page's name" do
    box = "<section><h2>Digital marketing strategy courses for small business owners</h2>" \
          "<div class='grid'>#{cards(stories, '/courses/')}</div></section>"

    blocks("<h1>Digital marketing strategy</h1>#{story(3)}#{box}", "https://example.org/digital-marketing-strategy/").should_not be_empty
  end

  it "does not take a title that leaves out some of the address's words for the page's name" do
    box = "<section><h2>Digital marketing strategy</h2><div class='grid'>#{cards(stories, '/news/')}</div></section>"

    blocks("<h1>What is digital marketing</h1>#{story(3)}#{box}", "https://example.org/what-is-digital-marketing/").should_not be_empty
  end

  it "keeps a hub's lists of the latest and more posts" do
    lists = ["Latest news", "More headphone posts"].map do |title|
      "<section class='#{title.split.first.downcase}'><h2>#{title}</h2>#{cards(stories.map { |story| "#{title}: #{story}" }, '/articles/')}</section>"
    end
    html = "<h1>Headphones</h1><p>Everything we write about headphones, from earbuds to studio cans.</p>#{lists.join}"

    blocks(html, "https://news.example.com/topic/headphones", nil).should be_empty
  end

  it "does not take percent escapes in a query value for an id" do
    terms = ["Building fittings -- Catalogs", "Cabinet hardware -- Catalogs", "Door fittings and locks -- Catalogs"]
    items = terms.map { |term| "<li><a href='browse?type=lcsubc&amp;key=#{term.gsub(' ', '%20')}'>#{term}</a></li>" }
    html = "<h1>Hardware -- Catalogs</h1>#{story(1)}<b>Narrower terms:</b><ul>#{items.join}</ul>"

    blocks(html, "https://books.example.edu/browse?type=lcsubc&key=Hardware%20--%20Catalogs", nil).should be_empty
  end

  it "keeps a category's products whose names end in a code of another kind" do
    products = stories.each_with_index.map do |title, index|
      "<div class='card'><img src='/img/#{index}.jpg' alt=''><h3><a href='/usb-hub-model-#{37_209 + index}.html'>" \
        "#{title}</a></h3><span>319 kr</span></div>"
    end
    html = "<h1>USB hubs for laptops</h1>#{story(1)}<h3>Popular picks</h3><div class='grid'>#{products.join}</div>"

    blocks(html, "https://shop.example.com/usb-a-hubs-for-laptops-g8893.html", nil).should be_empty
  end

  it "keeps a listing's titled list of bare links to pages like it" do
    areas = ["Addicks reservoir trails", "Buffalo Bayou park trails", "Cinco Ranch greenbelt trails"]
    links = areas.each_with_index.map { |area, index| "<li><a href='/directory/80155#{index}/area'>#{area}</a></li>" }
    routes = cards(stories, "/route/", "<p>9.4 mi, intermediate, rated four stars by riders.</p>")
    html = "<h1>Houston</h1><p>Recommended routes near Houston for every kind of rider.</p>" \
           "<div class='routes'>#{routes}</div><h3>Areas within Houston</h3><ul>#{links.join}</ul>"

    blocks(html, "https://trails.example.com/directory/8010427/houston", nil).should be_empty
  end

  it "looks for the titles of runs side by side in time linear in their wrapper" do
    photos = Array.new(1000) do |run|
      shape = run.to_s(26).tr("0-9a-p", "a-z")
      Array.new(3) do |index|
        "<div class='#{shape}'><a href='/photos/#{run}-#{index}'><img src='/img/#{run}-#{index}.jpg' alt=''></a></div>"
      end.join
    end
    started = cpu_time
    found = blocks("<h1>Harbor photos</h1><div class='wall'>#{photos.join}</div>", "https://news.example.com/photos/harbor")

    (cpu_time - started).should < 2
    found.should be_empty
  end

  it "asks whether the wrappers of runs hold the page's heading in time linear in the page" do
    groups = Array.new(2000) do |group|
      photos = Array.new(3) do |index|
        "<div class='photo'><a href='/photos/#{group}-#{index}'><img src='/img/#{group}-#{index}.jpg' alt=''></a></div>"
      end
      "<div class='group'>#{photos.join}</div>"
    end
    html = "<h1>Harbor photos</h1><div class='wall'><h2>Photos</h2>#{groups.join}</div>"
    started = cpu_time
    found = blocks(html, "https://news.example.com/photos/harbor")

    (cpu_time - started).should < 2
    found.should be_empty
  end

  it "asks about the copies of a misnested formatting element in time linear in their number" do
    groups = Array.new(5000) do |group|
      photos = Array.new(3) do |index|
        "<a href='/photos/#{group}-#{index}'><img src='/img/#{group}-#{index}.jpg' alt=''></a>"
      end
      "<p>#{photos.join}<span itemprop='articleBody'>Harbor</span></p>"
    end
    html = "<h1>Harbor photos</h1><p><font face='Arial'>Photos of the harbor</p>#{groups.join}"
    started = cpu_time
    found = blocks(html, "https://news.example.com/photos/harbor")

    (cpu_time - started).should < 3
    found.should be_empty
  end

  it "drops blocks from the copies of a misnested formatting element in time linear in their number" do
    boxes = Array.new(6000) do |index|
      "<p><a class='box' href='/news/#{index}'>Story number #{index}</a> Caption of the harbor story.</p>"
    end
    html = "<div class='main'><p><font face='Arial'>Photos of the harbor</p>#{boxes.join}</div>"
    body = Nokolexbor::HTML(html).at_css("body")
    Nokodown::Dom.assign_keys(body)
    keys = body.css(".box").map { |box| Nokodown::Dom.key(box) }.to_set
    started = cpu_time
    main = described_class.strip([body.at_css(".main")], keys).first

    (cpu_time - started).should < 1
    main.at_css(".box").should be_nil
    main.css("font").size.should == 6001
  end

  it "drops many blocks from one column in time linear in the column" do
    photos = "<figure><img src='/img/harbor.jpg' alt=''></figure>" * 1000
    boxes = Array.new(1000) { |index| "<div class='box'><a href='/news/#{index}'>Story number #{index}</a></div>" }
    html = "<html><body><div class='main'><div class='column'>#{photos}#{boxes.join}#{story(5)}</div></div></body></html>"
    body = Nokolexbor::HTML(html).at_css("body")
    Nokodown::Dom.assign_keys(body)
    keys = body.css(".box").map { |box| Nokodown::Dom.key(box) }.to_set
    started = cpu_time
    column = described_class.strip([body.at_css(".main")], keys).first.at_css(".column")

    (cpu_time - started).should < 1
    column.at_css(".box").should be_nil
    column.css("figure").size.should == 1000
  end
end

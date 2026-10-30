# frozen_string_literal: true

RSpec.describe Nokodown::ServiceLinks do
  def markdown(html, url: "https://www.example.com/shop/trail-stove")
    story = "<p>#{'The stove boils a litre of water in four minutes on a small canister of gas. ' * 3}</p>"
    page = "<html><head><title>Trail stove</title></head><body><h1>Trail stove</h1>#{story}#{html}</body></html>"
    Nokodown.to_markdown(page, url: url, title: false)
  end

  def lines(html, url: "https://www.example.com/shop/trail-stove")
    body = Nokolexbor::HTML("<html><body>#{html}</body></html>").at_css("body")
    Nokodown::Dom.assign_keys(body)
    described_class.blocks([body], url, "Trail stove").map { |node| Nokodown::Dom.text(node) }
  end

  it "removes lines of links to sign in, the cart or the feeds, whatever their label" do
    html = '<div>您需要登录后才可以回帖 <a href="/member.php?mod=logging&action=login">登录</a> | ' \
           '<a href="/member.php?mod=register">注册</a></div><p><a href="https://shop.example.com/cart.asp">View Cart (0)</a></p>' \
           '<div>Subscribe to: <a href="https://www.example.com/feeds/posts/default">Posts (Atom)</a></div>'

    text = markdown(html)
    ["登录", "View Cart", "Subscribe to"].each { |line| text.should_not include(line) }
  end

  it "keeps a sign-in link in a sentence, a menu's sign-in item and another site's sign-up" do
    html = '<p>Members can <a href="/login">log in</a> to see the trade price of every stove we stock.</p>' \
           '<ul><li><a href="/shop">Shop</a></li><li><a href="/login">Members</a></li></ul>' \
           '<p><a href="https://expo.example.org/register">Register for the outdoor expo</a></p>'

    lines(html).should be_empty
  end

  it "keeps the title or the date that service links sit beside" do
    html = '<div><h3>Trail kettle</h3><a href="/login">Log in for prices</a></div><p>5 June 2026 <a href="/feed/">RSS</a></p>'

    text = markdown(html)
    ["Trail kettle", "5 June 2026"].each { |line| text.should include(line) }
  end

  it "keeps a heading that carries a feed or sign-in link" do
    html = '<h2>Latest news <a href="/feed/">RSS</a></h2><ul><li>New burner</li><li>Winter sale</li></ul>'

    markdown(html).should include("Latest news")
  end

  it "keeps a table or a picture beside a register link" do
    html = '<div><table><tr><th>Size</th><th>Weight</th></tr><tr><td>Small</td><td>Light</td></tr></table>' \
           '<a href="/register">Register to order</a></div><div><img src="/stove.jpg" alt="Stove lit"><a href="/login">Log in</a></div>'

    text = markdown(html)
    text.should include("Small")
    text.should include("Stove lit")
  end

  it "keeps the page's title set beside a sign-in link" do
    html = '<div class="header-col"><div class="copy">Synopsis | Trail stove</div><a href="/login">Login</a> | ' \
           '<a href="/register">Sign up</a></div>'

    markdown(html).should include("Synopsis | Trail stove")
  end

  it "keeps an event's card that links to its sign-up page" do
    card = '<div class="col-md-4"><a href="/event/basic-training-558/register"><article class="card">' \
           "<h5>Basic training</h5><span>1 and 2 September 2026, online</span></article></a></div>"

    lines(card).should be_empty
  end

  it "keeps a block of more than a handful of service links, and everything on a page that is itself a service" do
    links = %w[login register cart checkout wishlist my-account feed].map { |path| "<a href=\"/#{path}\">#{path}</a>" }.join(" ")
    reset = '<p>Forgot your password? <a href="/lost-password">Reset it</a></p>'

    lines("<div>#{links}</div>").should be_empty
    lines(reset, url: "https://www.example.com/login").should be_empty
    lines(reset).should == ["Forgot your password? Reset it"]
  end

  it "reads a feed or a cart named after a tag or a category as an archive" do
    ["/feed/", "/blog/feeds/posts/default", "/news.rss", "/cart.asp", "/forum/ucp.php?mode=register"].each do |path|
      described_class.service?(path).should == true
    end
    ["/tag/atom/", "/category/rss/", "/tags/cart", "/feeds-and-speeds"].each { |path| described_class.service?(path).should == false }
  end
end

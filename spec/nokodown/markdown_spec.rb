# frozen_string_literal: true

RSpec.describe "Markdown conversion" do
  describe "text" do
    it "collapses whitespace like a browser" do
      convert("<p>  one\n   two  three  </p>").should == "one two three"
    end

    it "splits paragraphs on a double <br>" do
      convert("<div>first line<br>second line<br><br>next paragraph</div>").should == "first line\nsecond line\n\nnext paragraph"
    end

    it "escapes only characters that would change the meaning" do
      convert("<p>snake_case, 5 * 3, *starred*, `tick`, <b>bold</b></p>").should == "snake_case, 5 * 3, \\*starred\\*, \\`tick\\`, **bold**"
    end

    it "escapes text that would start a heading or a quote" do
      convert("<p># not a heading</p><p>&gt; not a quote</p>").should == "\\# not a heading\n\n\\> not a quote"
    end

    it "drops decorative separator lines" do
      convert("<p>above<br>-----<br>below</p>").should == "above\nbelow"
    end

    it "keeps superscripts and drops the tag from footnote markers" do
      convert("<p>10<sup>6</sup> cells, H<sub>2</sub>O, cited<sup>[1]</sup></p>").should == "10<sup>6</sup> cells, H<sub>2</sub>O, cited[1]"
    end
  end

  describe "emphasis" do
    it "moves surrounding spaces outside the markers" do
      convert("<p>a<strong> bold </strong>b <em>it</em></p>").should == "a **bold** b *it*"
    end

    it "does not bold headings or nest the same marker" do
      convert("<h2><b>Title</b></h2><p><b>a <strong>b</strong></b></p>").should == "## Title\n\n**a b**"
    end

    it "skips empty emphasis" do
      convert("<p>x<b> </b>y<i></i></p>").should == "x y"
    end
  end

  describe "links" do
    it "resolves relative URLs against the page URL" do
      convert('<p><a href="../guide">Guide</a> and <a href="/about">about</a></p>').should ==
        "[Guide](https://example.com/guide) and [about](https://example.com/about)"
    end

    it "strips click-tracking parameters" do
      convert('<p><a href="https://shop.example/p?id=7&utm_source=mail&gclid=abc">Item</a></p>').should == "[Item](https://shop.example/p?id=7)"
      convert('<p><a href="https://shop.example/p?id=7&_ga=2.1.2-3&srsltid=AfmBOx">Item</a></p>').should == "[Item](https://shop.example/p?id=7)"
    end

    it "shortens Amazon links to the product or the search" do
      product = "https://www.amazon.com/Trail-Boot/dp/B000O3LUEI/ref=sr_1_1?crid=2X&dib=eyJ2IjoiMSJ9.abc&qid=1&sr=8-1&tag=site-20&linkCode=ll1"
      convert(%(<p><a href="#{product}">Boot</a></p>)).should == "[Boot](https://www.amazon.com/Trail-Boot/dp/B000O3LUEI?tag=site-20)"
      search = "https://www.amazon.com/s/ref=nb_sb_noss?k=trail+boot&crid=2X&qid=1&ref=sr_pg_1"
      convert(%(<p><a href="#{search}">Boots</a></p>)).should == "[Boots](https://www.amazon.com/s?k=trail+boot)"
      convert('<p><a href="https://WWW.AMAZON.CO.UK/dp/B000O3LUEI?psc=1">Boot</a></p>').should == "[Boot](https://WWW.AMAZON.CO.UK/dp/B000O3LUEI)"
    end

    it "keeps Amazon parameter names on other sites and other Amazon services" do
      href = "https://go.microsoft.com/fwlink/?linkid=2300933"
      convert(%(<p><a href="#{href}">Docs</a></p>)).should == "[Docs](#{href})"
      aws = "https://docs.aws.amazon.com/ec2/ref=guide?sr=1&qid=2"
      convert(%(<p><a href="#{aws}">EC2</a></p>)).should == "[EC2](#{aws})"
    end

    it "leaves a query without tracking parameters as written" do
      href = "https://example.com/search?a=1&&b=2&"
      convert(%(<p><a href="#{href}">Search</a></p>)).should == "[Search](#{href})"
    end

    it "unwraps known click redirectors" do
      html = '<p><a href="https://www.google.com/url?q=https%3A%2F%2Fexample.org%2Fdoc%3Fid%3D3&sa=D&usg=AOv">Doc</a> ' \
             '<a href="https://go.skimresources.com/?id=1X2&url=https%3A%2F%2Fshop.example%2Fkettle%3Futm_source%3Dskim">Kettle</a></p>'
      convert(html).should == "[Doc](https://example.org/doc?id=3) [Kettle](https://shop.example/kettle)"
    end

    it "takes the redirect destination from the first parameter that holds a URL" do
      href = "https://www.google.com/url?sa=t&q=&esrc=s&url=https%3A%2F%2Fexample.org%2Fdoc&usg=AOv"
      convert(%(<p><a href="#{href}">Doc</a></p>)).should == "[Doc](https://example.org/doc)"
    end

    it "keeps redirects whose destination is not valid UTF-8" do
      latin1 = "https://www.google.com/url?q=https%3A%2F%2Fexample.org%2Fcaf%E9&sa=D"
      truncated = "https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.org%2Fcaf%E2%80"
      convert(%(<p><a href="#{latin1}">Cafe</a> <a href="#{truncated}">Menu</a></p>)).should == "[Cafe](#{latin1}) [Menu](#{truncated})"
    end

    it "recognises links back to the page when only tracking parameters differ" do
      html = '<body><p>See <a href="https://example.com/post#comments">comments</a>.</p></body>'
      Nokodown.to_markdown(html, url: "https://example.com/post?utm_source=feed", main_content: false, title: false).should == "See comments."
      product = "https://www.amazon.com/Trail-Boot/dp/B000O3LUEI/ref=sr_1_1?qid=1&sr=8-1"
      html = '<body><p>Read <a href="#customerReviews">reviews</a>.</p></body>'
      Nokodown.to_markdown(html, url: product, main_content: false, title: false).should == "Read reviews."
    end

    it "keeps only the text of in-page anchors, scripts and phone links" do
      convert('<p><a href="#top">Top</a> <a href="javascript:void(0)">Open</a> <a href="tel:+1555">Call</a></p>').should == "Top Open Call"
    end

    it "drops permalink symbols and read-more links" do
      convert('<h2>Setup<a href="#setup">¶</a></h2><p>Intro. <a href="/post">Read more »</a></p>').should == "## Setup\n\nIntro."
    end

    it "writes a link whose text is its URL as a bare URL" do
      convert('<p><a href="https://example.org/">example.org</a></p>').should == "https://example.org/"
    end

    it "puts images out of link text" do
      convert('<p><a href="/p/1"><img src="/1.jpg" alt="Boot"> Trail boot</a></p>').should ==
        "![Boot](https://example.com/1.jpg) [Trail boot](https://example.com/p/1)"
    end

    it "links the headline of a card wrapped in one link" do
      convert('<a href="/post"><h3>Headline</h3><p>Summary text</p></a>').should == "### [Headline](https://example.com/post)\n\nSummary text"
    end

    it "encodes spaces and unbalanced parentheses in URLs" do
      convert('<p><a href="/a b(c">x</a> <a href="/wiki/Ruby_(language)">y</a></p>').should ==
        "[x](https://example.com/a%20b%28c) [y](https://example.com/wiki/Ruby_(language))"
    end
  end

  describe "images" do
    it "uses lazy-loading attributes over placeholders" do
      convert('<img src="data:image/gif;base64,R0lGODlhAQABAAAAACw=" data-src="/real.jpg" alt="Real">').should == "![Real](https://example.com/real.jpg)"
    end

    it "takes the largest srcset candidate when there is no src" do
      convert('<img srcset="/s.jpg 320w, /l.jpg 1280w, /m.jpg 640w" alt="Photo">').should == "![Photo](https://example.com/l.jpg)"
    end

    it "drops tracking pixels, icons, placeholders and badges" do
      html = '<img src="/pixel.gif" width="1" height="1"><img src="/icon.png" width="16" height="16">' \
             '<img src="/assets/grey-placeholder.png"><img src="https://img.shields.io/badge/ci-passing-green" alt="CI">' \
             '<img src="/arrow.svg"><p>Text</p>'
      convert(html).should == "Text"
    end

    it "uses the alt text of emoji images" do
      convert('<p>Done <img class="wp-smiley" src="/e.png" alt="🎉"></p>').should == "Done 🎉"
    end

    it "drops repeated responsive variants of one image" do
      html = '<figure><img src="/a-small.jpg" alt="Harbour at dawn"><figcaption>Credit</figcaption>' \
             '<img src="/a-large.jpg" alt="Harbour at dawn"><figcaption>Credit</figcaption></figure>'
      convert(html).should == "![Harbour at dawn](https://example.com/a-small.jpg)\n\nCredit"
    end

    it "drops image CDN size, quality and version parameters" do
      convert('<img src="https://cdn.shop.example/files/kettle.jpg?v=1549149242&width=640&q=75" alt="Kettle">').should ==
        "![Kettle](https://cdn.shop.example/files/kettle.jpg)"
    end

    it "uses the original image behind Next.js, fetch and Cloudflare proxies" do
      html = '<p><img src="/_next/image?url=%2Fimages%2Fkettle.png&w=3840&q=75" alt="Kettle"> ' \
             '<img src="https://res.cloudinary.com/demo/image/fetch/w_800,q_auto/https://cdn.example.org/mug.png" alt="Mug"> ' \
             '<img src="https://cdn.example.net/image/fetch/w_36/https%3A%2F%2Fmedia.example.org%2Fcup.png" alt="Cup"> ' \
             '<img src="/cdn-cgi/image/width=800,quality=75/uploads/pot.jpg" alt="Pot"></p>'
      convert(html).should == "![Kettle](https://example.com/images/kettle.png) ![Mug](https://cdn.example.org/mug.png) " \
                              "![Cup](https://media.example.org/cup.png) ![Pot](https://example.com/uploads/pot.jpg)"
    end

    it "keeps the query of a fetched original that is not encoded" do
      src = "https://res.cloudinary.com/demo/image/fetch/w_800/https://cdn.example.org/render.php?id=7"
      convert(%(<img src="#{src}" alt="Chart">)).should == "![Chart](https://cdn.example.org/render.php?id=7)"
    end

    it "keeps screenshot and archive URLs that embed a page URL" do
      shot = "https://s.example.com/mshots/v1/https%3A%2F%2Fexample.org"
      archive = "https://web.archive.org/web/2020im_/https://example.org/logo.png"
      convert(%(<p><img src="#{shot}" alt="Site"> <img src="#{archive}" alt="Logo"></p>)).should == "![Site](#{shot}) ![Logo](#{archive})"
    end

    it "keeps image proxies whose original is not a web URL" do
      data = "/_next/image?url=data%3Aimage%2Fgif%3Bbase64%2CR0lGOD&w=64&q=75"
      script = "/_next/image?url=javascript%3Aalert(1)&w=64&q=75"
      latin1 = "/_next/image?url=%2Fcaf%E9.png&w=64&q=75"
      convert(%(<p><img src="#{data}" alt="Dot"> <img src="#{script}" alt="Icon"> <img src="#{latin1}" alt="Cafe"></p>)).should ==
        "![Dot](https://example.com#{data}) ![Icon](https://example.com#{script}) ![Cafe](https://example.com#{latin1})"
      convert('<img src="/_next/image?url=%23top&w=64" alt="Top">').should include("/_next/image?url=%23top")
    end

    it "keeps signed image URLs as they are" do
      s3 = "https://bucket.s3.amazonaws.com/chart.png?w=800&X-Amz-Signature=0f3a9c"
      imgix = "https://img.evbuc.com/https%3A%2F%2Fcdn.evbuc.com%2Fimages%2F1%2Foriginal.jpg?w=460&s=ccc672"
      convert(%(<p><img src="#{s3}" alt="Chart"> <img src="#{imgix}" alt="Event"></p>)).should == "![Chart](#{s3}) ![Event](#{imgix})"
      gcs = "https://storage.googleapis.com/b/map.png?X-Goog-Expires=900&X-Goog-Signature=0f3a9c&width=800"
      akamai = "https://img.example.net/team.jpg?imwidth=800&__token__=exp%3D1~hmac%3D0f3a9c"
      convert(%(<p><img src="#{gcs}" alt="Map"> <img src="#{akamai}" alt="Team"></p>)).should == "![Map](#{gcs}) ![Team](#{akamai})"
    end
  end

  describe "lists" do
    it "renders nested lists with indentation" do
      convert("<ul><li>One<ul><li>One A</li></ul></li><li>Two</li></ul>").should == "- One\n  - One A\n- Two"
    end

    it "numbers ordered lists from their start attribute" do
      convert('<ol start="3"><li>c</li><li>d</li></ol>').should == "3. c\n4. d"
    end

    it "separates items holding several paragraphs" do
      convert("<ol><li><p>First</p><p>More</p></li><li><p>Second</p></li></ol>").should == "1. First\n\n   More\n\n2. Second"
    end

    it "looks through wrappers between the list and its items" do
      convert("<ul><div><li>a</li><li>b</li></div></ul>").should == "- a\n- b"
    end

    it "renders task list checkboxes" do
      convert('<ul><li><input type="checkbox" checked> Done</li><li><input type="checkbox"> Todo</li></ul>').should == "- [x] Done\n- [ ] Todo"
    end

    it "renders definition lists as term and definition pairs" do
      convert("<dl><dt>Weight</dt><dd>540 g</dd><dt>Colors</dt><dd>Brown</dd><dd>Black</dd></dl>").should ==
        "- **Weight**: 540 g\n- **Colors**: Brown; Black"
    end
  end

  describe "code" do
    it "fences preformatted code and keeps its language" do
      convert(%(<pre><code class="language-python">def f():\n    return 1</code></pre>)).should == "```python\ndef f():\n    return 1\n```"
    end

    it "reads the language from wrappers used by GitHub and Sphinx" do
      convert('<div class="highlight-shell"><div class="highlight"><pre>ls -la</pre></div></div>').should == "```shell\nls -la\n```"
    end

    it "uses a longer fence when the code contains one" do
      convert("<pre>```\ninner\n```</pre>").should == "````\n```\ninner\n```\n````"
    end

    it "puts each line of block-per-line highlighters on its own line" do
      convert('<pre><div class="line">a = 1</div><div class="line">b = 2</div></pre>').should == "```\na = 1\nb = 2\n```"
    end

    it "drops line numbers" do
      convert('<pre><span class="linenos">1</span>puts 1</pre>').should == "```\nputs 1\n```"
    end

    it "wraps inline code containing backticks in a longer fence" do
      convert("<p>Use <code>`x`</code> here</p>").should == "Use `` `x` `` here"
    end
  end

  describe "tables" do
    it "renders data tables as GFM tables, escaping pipes" do
      convert("<table><tr><th>Key</th><th>Value</th></tr><tr><td>a|b</td><td>1</td></tr></table>").should ==
        "| Key | Value |\n| --- | --- |\n| a\\|b | 1 |"
    end

    it "carries rowspans down and leaves colspans blank" do
      html = "<table><thead><tr><th>Group</th><th>Item</th><th>Qty</th></tr></thead>" \
             '<tr><td rowspan="2">Fruit</td><td>Apple</td><td>3</td></tr><tr><td>Pear</td><td>5</td></tr>' \
             '<tr><td colspan="2">Total</td><td>8</td></tr></table>'
      convert(html).should == "| Group | Item | Qty |\n| --- | --- | --- |\n| Fruit | Apple | 3 |\n| Fruit | Pear | 5 |\n| Total |  | 8 |"
    end

    it "unwraps layout tables" do
      convert('<table role="presentation"><tr><td><p>Left column</p></td><td><p>Right column</p></td></tr></table>').should ==
        "Left column\n\nRight column"
    end

    it "keeps the caption" do
      convert("<table><caption>Results</caption><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>").should ==
        "Results\n\n| A | B |\n| --- | --- |\n| 1 | 2 |"
    end
  end

  describe "other blocks" do
    it "prefixes every line of a blockquote" do
      convert("<blockquote><p>One</p><p>Two</p></blockquote>").should == "> One\n>\n> Two"
    end

    it "keeps one rule between blocks" do
      convert("<hr><p>a</p><hr><hr><p>b</p><hr>").should == "a\n\n---\n\nb"
    end

    it "renders details with a bold summary" do
      convert("<details><summary>More info</summary><p>Hidden detail</p></details>").should == "**More info**\n\nHidden detail"
    end

    it "links embedded videos to their page" do
      convert('<iframe src="https://www.youtube.com/embed/dQw4w9WgXcQ" title="Demo video"></iframe>').should ==
        "[Demo video](https://www.youtube.com/watch?v=dQw4w9WgXcQ)"
    end

    it "uses the TeX source of MathML" do
      math = '<math><semantics><mi>x</mi><annotation encoding="application/x-tex">x^2</annotation></semantics></math>'
      convert("<p>Area #{math}</p>").should == "Area $x^2$"
    end

    it "drops a trailing heading left without content" do
      convert("<h2>Intro</h2><p>Text</p><h2>Related</h2>").should == "## Intro\n\nText"
    end
  end
end

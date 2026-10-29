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

    it "escapes a lone asterisk or underscore only where it would start a list" do
      convert("<p>2011* <i>a</i></p><p>Leser*innen</p><p>**Ontdek</p><p>!_Tokyo, \u09AC\u09BE_\u09A6</p><p>* note</p><p>5*21*19</p>").should ==
        "2011\\* *a*\n\nLeser*innen\n\n**Ontdek\n\n!_Tokyo, \u09AC\u09BE_\u09A6\n\n\\* note\n\n5\\*21\\*19"
    end

    it "escapes text that would start a heading or a quote" do
      convert("<p># not a heading</p><p>&gt; not a quote</p>").should == "\\# not a heading\n\n\\> not a quote"
    end

    it "spaces words that adjacent elements run together" do
      html = '<p><a href="/t/1">Song for Wife</a><a href="/t/2">Personalized Song</a></p><p><a href="/u/admin">admin</a>24/04/2022</p>' \
             "<p><b>20h30</b><b>vendredi</b>, i<b>NP</b>ut, j<b>ährlich</b>, 2024<span>年</span>, Model<span>3</span></p>"
      convert(html).should == "[Song for Wife](https://example.com/t/1) [Personalized Song](https://example.com/t/2)\n\n" \
                              "[admin](https://example.com/u/admin) 24/04/2022\n\n**20h30 vendredi**, i**NP**ut, j**ährlich**, 2024年, Model 3"
    end

    it "drops joiners outside words and emoji" do
      convert("<p>\u200D<b>Rights</b></p><p>\u0645\u06CC\u200C\u062E\u0648\u0627\u0647\u0645 \u{1F468 200D 1F469}</p>").should ==
        "**Rights**\n\n\u0645\u06CC\u200C\u062E\u0648\u0627\u0647\u0645 \u{1F468 200D 1F469}"
    end

    it "drops icon-font glyphs and ligatures" do
      convert('<p>&#xE001; Next <i class="material-icons">arrow_forward</i></p>').should == "Next"
    end

    it "drops decorative separator lines" do
      convert("<p>above<br>-----<br>below</p>").should == "above\nbelow"
    end

    it "drops lines of only punctuation and operators" do
      convert("<p>a<br>|<br>~<br>- -&gt;<br>👍<br>b</p><ul><li>|</li><li>c</li></ul>").should == "a\n👍\nb\n\n- c"
    end

    it "drops separators between links and at the ends of lines" do
      convert('<p>by | Oct 7, 2011 |</p><p><a href="/a">A</a> | <a href="/b">B</a> · <a href="/c">C</a></p><p>Volume 13 | Issue 1</p>').should ==
        "by | Oct 7, 2011\n\n[A](https://example.com/a) [B](https://example.com/b) [C](https://example.com/c)\n\nVolume 13 | Issue 1"
    end

    it "writes raised and lowered digits as Unicode characters and drops the tag from footnote markers" do
      convert("<p>10<sup>-6</sup> cells, H<sub>2</sub>O, cited<sup>[1]</sup></p>").should == "10⁻⁶ cells, H₂O, cited[1]"
    end

    it "marks other raised words with a caret and leaves ordinals and symbols as text" do
      convert("<p>x<sup>n</sup>, the 21<sup>st</sup> Acme<sup>®</sup>, <sub>small print</sub></p>").should == "x^n, the 21st Acme®, small print"
    end

    it "groups raised and lowered expressions so they keep their meaning" do
      convert("<p>2<sup>n-1</sup>, 2<sup>n - 1</sup>, x<sup>i=1</sup>, a<sub>n</sub>, a<sub>n+1</sub></p>").should ==
        "2^(n-1), 2^(n - 1), x^(i=1), a_n, a_(n+1)"
    end

    it "groups decimals, comma-separated indices, products and scripts followed by a letter" do
      html = "<p>10<sup>2.5</sup>, 10<sup>-0.5</sup>, O(n<sup>2.373</sup>), a<sub>i,j</sub>, Smith<sup>a,b</sup>, " \
             "e<sup>(x-1)(x+1)</sup>, e<sup>(n-1)</sup>, x<sub>i</sub>y<sub>i</sub></p>"
      convert(html).should == "10^(2.5), 10^(-0.5), O(n^(2.373)), a_(i,j), Smith a,b, e^((x-1)(x+1)), e^(n-1), x_(i)y_i"
    end

    it "reads formatted scripts by their text" do
      convert("<p>2<sup><i>p</i></sup> &minus; 1, M<sub><i>p</i></sub>, <i>x</i><sup><i>n</i></sup>, 2<sup><i>n</i>&minus;1</sup></p>").should ==
        "2^p − 1, M_p, *x*^n, 2^(n−1)"
    end

    it "keeps other raised words apart from the words around them and badges after a space as text" do
      html = "<p>Smith<sup>a, b</sup>, studies<sup>1–3</sup>, Feature <sup>NEW</sup>, Feature <sup><b>NEW</b></sup></p><p><sup>a</sup>Adjusted</p>"
      convert(html).should == "Smith a, b, studies 1–3, Feature NEW, Feature **NEW**\n\na Adjusted"
    end

    it "writes footnote letters and badges after a word or a bracket as text, not as exponents" do
      html = "<p>20.02 (6.16)<sup>b</sup>, Age (years)<sup>a</sup>, <a href='https://aur.example/p'>pacman-static</a><sup>AUR</sup>, Trade-In<sup>Δ</sup>, " \
             "A<sup>H</sup>A, (x+1)<sup>n-1</sup></p>"
      convert(html).should == "20.02 (6.16) b, Age (years) a, [pacman-static](https://aur.example/p) AUR, Trade-In Δ, A^(H)A, (x+1)^(n-1)"
    end

    it "groups nested scripts and escapes a subscript after emphasis" do
      convert("<p>e<sup>-x<sup>2</sup></sup>, 2<sup>2<sup><i>n</i></sup></sup> + 1, x<sup>a<sub>i</sub></sup></p>").should ==
        "e^(-x²), 2^(2^n) + 1, x^(a_i)"
      convert("<p><i>x</i><sub><i>i</i></sub> + a<sub>n+1</sub></p>").should == "*x*\\_i + a_(n+1)"
      convert("<p>^ <sup><i><b>a</b></i></sup> <sup><i><b>b</b></i></sup> Source</p>").should == "^ ***a*** ***b*** Source"
    end

    it "writes raised cents after a price as decimals" do
      html = "<p>$549<sup>99</sup>, <span>$2,799</span><sup>00</sup>, <sup>$</sup>19<sup>95</sup>, the 10<sup>15</sup> scale, " \
             "€12,<sup>99</sup>, 549<sup>99</sup> €</p>"
      convert(html).should == "$549.99, $2,799.00, $19.95, the 10¹⁵ scale, €12,99, 549.99 €"
    end

    it "reads cents after European amounts, currency codes and spaced spans" do
      html = "<p>1.299<sup>99</sup> €, € 1.299<sup>99</sup>, CHF 49<sup>90</sup>, <span>$</span>\n<span>549</span>\n<sup>99</sup></p>"
      convert(html).should == "1.299,99 €, € 1.299,99, CHF 49.90, $ 549 .99"
    end

    it "keeps Spanish and Portuguese ordinals as text" do
      convert("<p>1<sup>a</sup> edición, 2<sup>do</sup> lugar, 1<sup>ª</sup> vez</p>").should == "1a edición, 2do lugar, 1ª vez"
    end

    it "keeps French and wrapped ordinals and titles as text and uses the characters for raised o, degrees and TM" do
      html = "<p>le 1<sup>er</sup> mai, le XIX<sup>e</sup> siècle, M<sup>me</sup> Roux, the 21<span><sup>st</sup></span>, " \
             "1<sup>o</sup> piso, 30<sup>o</sup>C, Acme<sup>TM</sup>, Bar<sup>tm</sup></p>"
      convert(html).should == "le 1er mai, le XIXe siècle, Mme Roux, the 21st, 1º piso, 30°C, Acme™, Bar™"
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

    it "joins runs a page split in two" do
      convert("<p>a <b>tw</b><b>o</b> <b>three</b> <b>four</b> <i>five</i> <i>six</i></p>").should == "a **two three four** *five six*"
    end

    it "drops emphasis around a whole paragraph but keeps a bold label" do
      html = "<p><i>The whole paragraph is set in italics.</i></p><p><b>Ingredients</b></p><p><b>Mix the flour and the eggs.</b></p>" \
             "<p><i><b>Note:</b> it rises.</i></p><p><b><i>Serves</i></b></p>"
      convert(html).should == "The whole paragraph is set in italics.\n\n**Ingredients**\n\nMix the flour and the eggs.\n\n**Note:** it rises.\n\n**Serves**"
    end

    it "drops emphasis around a whole list item, table cell, heading or link text" do
      html = "<ul><li><b>Bold item</b></li></ul><table><tr><th><b>Key</b></th><th>Value</th></tr><tr><td><b>a</b></td><td><i>1</i></td></tr></table>" \
             '<h2><i>Title</i></h2><p>See <b><a href="/a">this</a></b> and <a href="/b"><i>that</i></a>.</p>'
      convert(html).should == "- Bold item\n\n| Key | Value |\n| --- | --- |\n| a | 1 |\n\n## Title\n\n" \
                              "See [this](https://example.com/a) and [that](https://example.com/b)."
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
      isbn = "https://www.amazon.com/dp/9781234567890/ref=sr_1_1?qid=1"
      convert(%(<p><a href="#{isbn}">Book</a></p>)).should == "[Book](https://www.amazon.com/dp/9781234567890)"
      ranking = "https://www.amazon.com/gp/bestsellers/ref=zg_bs_nav/books/123"
      convert(%(<p><a href="#{ranking}">Books</a></p>)).should == "[Books](#{ranking})"
      author = "https://www.amazon.com/Jane-Doe/e/B00HVQPIH6/ref=zg_bs_g_books_1/131-7552878-9432557"
      convert(%(<p><a href="#{author}">Jane Doe</a></p>)).should == "[Jane Doe](https://www.amazon.com/Jane-Doe/e/B00HVQPIH6)"
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
      convert('<p><a href="https://WWW.GOOGLE.COM/url?q=https%3A%2F%2Fexample.org%2Fdoc">Doc</a></p>').should == "[Doc](https://example.org/doc)"
    end

    it "takes the redirect destination from the first parameter that holds a URL" do
      href = "https://www.google.com/url?sa=t&q=&esrc=s&url=https%3A%2F%2Fexample.org%2Fdoc&usg=AOv"
      convert(%(<p><a href="#{href}">Doc</a></p>)).should == "[Doc](https://example.org/doc)"
    end

    it "unwraps at most three nested redirects" do
      href = "https://example.org/doc"
      4.times { href = "https://www.google.com/url?q=#{URI.encode_www_form_component(href)}" }
      convert(%(<p><a href="#{href}">Doc</a></p>)).should == "[Doc](https://www.google.com/url?q=https%3A%2F%2Fexample.org%2Fdoc)"
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

    it "drops permalink marks before or after heading text" do
      convert('<h2>Setup <a href="#setup">#</a></h2><p>a</p><h3><a href="#run">¶</a> Run</h3><p>b</p><h3>#Shots</h3><p>6</p>').should ==
        "## Setup\n\na\n\n### Run\n\nb\n\n### #Shots\n\n6"
    end

    it "drops separators and arrows at the ends of link text" do
      html = '<p><a href="/f">Forum |</a> <a href="/j">· Jobs</a> <a href="/m">Learn more →</a> <a href="/n">»</a> ' \
             '<a href="/v">Voir ›</a> <a href="/q">«Rycari 2017»</a></p>'
      convert(html).should == "[Forum](https://example.com/f) [Jobs](https://example.com/j) [Learn more](https://example.com/m) " \
                              "[Voir](https://example.com/v) [«Rycari 2017»](https://example.com/q)"
    end

    it "keeps a card's link on its title and drops the buttons that repeat it" do
      card = '<li><a href="/p/1">2 options</a><h3><a href="/p/1">Trail boot</a></h3><p>Leather for rocky ground <a href="/p/1">…</a> ' \
             '<a href="/p/1/">Weiterlesen</a></p><p>Try <a href="/p/1">this one</a> today.</p></li>'
      convert("<ul>#{card}</ul><h2>Edge</h2><p>7 octobre</p><p><a href=\"/e/edge\">Voir</a></p>").should ==
        "- 2 options\n  [Trail boot](https://example.com/p/1)\n  Leather for rocky ground …\n  Try this one today.\n\n" \
        "## Edge\n\n7 octobre\n\n[Voir](https://example.com/e/edge)"
    end

    it "keeps the links to other sections of a page and spaces the links it unwraps" do
      html = '<p><a href="/g#1">One</a> <a href="/g#2">Two</a></p><p><a href="/a">apples</a><a href="/b">pears</a><a href="/a">fruit</a> ' \
             'and more on <a href="/a">apples</a>.</p>'
      convert(html).should == "[One](https://example.com/g#1) [Two](https://example.com/g#2)\n\n" \
                              "[apples](https://example.com/a)[pears](https://example.com/b) fruit and more on apples."
    end

    it "writes a mail link that shows its address as text" do
      convert('<p><a href="mailto:info@g-stroot.de">E-Mail info@g-stroot.de</a>, <a href="mailto:a@b.co">Write us</a></p>').should ==
        "E-Mail info@g-stroot.de, [Write us](mailto:a@b.co)"
    end

    it "decodes addresses Cloudflare hides" do
      html = '<p><a href="/cdn-cgi/l/email-protection#5a33343c351a3f223b372a363f74393537">[email&#160;protected]</a>, ' \
             '<span class="__cf_email__" data-cfemail="5a33343c351a3f223b372a363f74393537">[email&#160;protected]</span></p>'
      convert(html).should == "info@example.com, info@example.com"
    end

    it "writes a link whose text is its URL as a bare URL" do
      convert('<p><a href="https://example.org/">example.org</a></p>').should == "https://example.org/"
    end

    it "writes a link whose text is a whole address as that address" do
      html = '<p><a href="https://track.example.net/ct?url=x&amp;id=9">https://www.bar.example/</a> ' \
             '<a href="https://example.org/a/very/long/path">https://example.org/a/very/…</a></p>'
      convert(html).should == "https://www.bar.example/ [https://example.org/a/very/…](https://example.org/a/very/long/path)"
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

    it "uses the <noscript> copy of a lazy image once, on either side of the placeholder" do
      html = '<p><noscript><img src="/a.jpg" alt="Harbour"></noscript>' \
             '<img class="lazyload" src="data:image/gif;base64,R0lGODlhAQABAAAAACw=" data-src="/a.jpg" alt="Harbour">' \
             '<noscript><img src="/b.jpg" alt="Pier"></noscript><img class="lazyload" data-src="/b.jpg" alt="Pier"></p>' \
             '<p><img class="lazyload" data-src="/c-small.jpg" alt="Quay"><noscript><img src="/c.jpg" alt="Quay"></noscript></p>'
      convert(html).should == "![Harbour](https://example.com/a.jpg)![Pier](https://example.com/b.jpg)\n\n![Quay](https://example.com/c.jpg)"
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

    it "drops markup written into alt text" do
      convert('<p><img src="/a.jpg" alt="<p>Design <b>the</b> solution</p>"></p>').should == "![Design the solution](https://example.com/a.jpg)"
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
      convert('<img src="https://cdn.shop.example/files/kettle.jpg?v=1549149242&width=640&q=75&fm=webp" alt="Kettle">').should ==
        "![Kettle](https://cdn.shop.example/files/kettle.jpg)"
    end

    it "keeps image parameters that name the picture or its required format" do
      google = "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQabc&usqp=CAU"
      bing = "https://tse1.mm.bing.net/th?q=red+kettle&w=120&h=120&c=1"
      twitter = "https://pbs.twimg.com/media/GabcXYZ?format=jpg&name=small"
      convert(%(<p><img src="#{google}" alt="Kettle"> <img src="#{bing}" alt="Red kettle"> <img src="#{twitter}" alt="Photo"></p>)).should ==
        "![Kettle](#{google}) ![Red kettle](https://tse1.mm.bing.net/th?q=red+kettle&c=1) ![Photo](#{twitter})"
    end

    it "drops tracking parameters from images" do
      html = '<p><img src="https://cdn.example.org/a.jpg?utm_source=mail&id=3" alt="A"> ' \
             '<img src="https://cdn.example.org/b.jpg?fbclid=IwAR0" alt="B"> ' \
             '<img src="https://cdn.example.org/c.jpg?w=800&utm_source=mail" alt="C"></p>'
      convert(html).should == "![A](https://cdn.example.org/a.jpg?id=3) ![B](https://cdn.example.org/b.jpg) ![C](https://cdn.example.org/c.jpg)"
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

    it "keeps the query of a relative Cloudflare original" do
      convert('<img src="/cdn-cgi/image/width=800/render.php?id=7" alt="Chart">').should == "![Chart](https://example.com/render.php?id=7)"
    end

    it "keeps the options of unknown proxies and of originals in private buckets" do
      resize = "https://img.example.net/imaginary/resize?width=400&height=200&type=webp&url=https://example.org/chart.png"
      bucket = "https://substackcdn.com/image/fetch/w_36/https%3A%2F%2Fbucketeer-e05b.s3.amazonaws.com%2Fpublic%2Fimages%2Fc3.jpeg"
      convert(%(<p><img src="#{resize}" alt="Chart"> <img src="#{bucket}" alt="Author"></p>)).should == "![Chart](#{resize}) ![Author](#{bucket})"
    end

    it "keeps screenshot and archive URLs that embed a page URL" do
      shot = "https://s.example.com/mshots/v1/https%3A%2F%2Fexample.org"
      archive = "https://web.archive.org/web/2020im_/https://example.org/logo.png"
      convert(%(<p><img src="#{shot}" alt="Site"> <img src="#{archive}" alt="Logo"></p>)).should == "![Site](#{shot}) ![Logo](#{archive})"
    end

    it "keeps image proxies whose original is not a web URL or is the proxy itself" do
      data = "/_next/image?url=data%3Aimage%2Fgif%3Bbase64%2CR0lGOD&w=64&q=75"
      script = "/_next/image?url=javascript%3Aalert(1)&w=64&q=75"
      latin1 = "/_next/image?url=%2Fcaf%E9.png&w=64&q=75"
      convert(%(<p><img src="#{data}" alt="Dot"> <img src="#{script}" alt="Icon"> <img src="#{latin1}" alt="Cafe"></p>)).should ==
        "![Dot](https://example.com#{data}) ![Icon](https://example.com#{script}) ![Cafe](https://example.com#{latin1})"
      convert('<img src="/_next/image?url=%23top&w=64" alt="Top">').should == "![Top](https://example.com/_next/image?url=%23top&w=64)"
    end

    it "keeps signed image URLs as they are" do
      s3 = "https://bucket.s3.amazonaws.com/chart.png?w=800&X-Amz-Signature=0f3a9c"
      imgix = "https://img.evbuc.com/https%3A%2F%2Fcdn.evbuc.com%2Fimages%2F1%2Foriginal.jpg?w=460&s=ccc672"
      convert(%(<p><img src="#{s3}" alt="Chart"> <img src="#{imgix}" alt="Event"></p>)).should == "![Chart](#{s3}) ![Event](#{imgix})"
      gcs = "https://storage.googleapis.com/b/map.png?X-Goog-Expires=900&X-Goog-Signature=0f3a9c&width=800"
      akamai = "https://img.example.net/team.jpg?imwidth=800&__token__=exp%3D1~hmac%3D0f3a9c"
      convert(%(<p><img src="#{gcs}" alt="Map"> <img src="#{akamai}" alt="Team"></p>)).should == "![Map](#{gcs}) ![Team](#{akamai})"
    end

    it "drops later copies of an image standing alone, such as a logo strip rendered twice" do
      html = '<h2>Trusted by</h2><ul><li><img src="/acme.png" alt="Acme"></li><li><img src="/globex.png" alt="Globex"></li></ul>' \
             '<div><img src="/acme.png" alt="Acme"><img src="/globex.png" alt="Globex"></div>' \
             '<p>Rated <img src="/star.png" alt="star"><img src="/star.png" alt="star"> by 2,000 teams</p>'
      convert(html).should == "## Trusted by\n\n- ![Acme](https://example.com/acme.png)\n- ![Globex](https://example.com/globex.png)\n\n" \
                              "Rated ![star](https://example.com/star.png)![star](https://example.com/star.png) by 2,000 teams"
    end

    it "keeps every row of rating stars whole, however often a row repeats" do
      row = ->(full) { ('<img src="/star.png" alt="star">' * full) + ('<img src="/star-empty.png" alt="empty star">' * (5 - full)) }
      stars = ->(full) { ("![star](https://example.com/star.png)" * full) + ("![empty star](https://example.com/star-empty.png)" * (5 - full)) }
      ratings = [4, 2, 5, 4]
      html = ratings.each_with_index.map { |full, i| "<div class=\"rating\">#{row.call(full)}</div><p>Review #{i + 1}</p>" }.join
      convert(html).should == ratings.each_with_index.map { |full, i| "#{stars.call(full)}\n\nReview #{i + 1}" }.join("\n\n")
    end

    it "keeps a badge with alt text on each post, but drops later copies of an image without one" do
      html = %w[Member Moderator Member].each_with_index.map do |role, i|
        "<div><img src=\"/#{role.downcase}.png\" alt=\"#{role}\"><img src=\"/online.png\" alt=\"\"></div><p>Post #{i + 1}</p>"
      end.join
      convert(html).should == "![Member](https://example.com/member.png)![](https://example.com/online.png)\n\nPost 1\n\n" \
                              "![Moderator](https://example.com/moderator.png)\n\nPost 2\n\n![Member](https://example.com/member.png)\n\nPost 3"
    end

    it "keeps nested list markers when it drops a repeated image" do
      html = '<p><img src="https://ex.com/avatar.png"> Forum</p><ol><li><p>First post</p></li>' \
             '<li><ol><li><ul><li><img src="https://ex.com/avatar.png"><p>Reply</p></li></ul></li></ol></li></ol>'
      convert(html).should == "![](https://ex.com/avatar.png) Forum\n\n1. First post\n   1. - Reply"
    end

    it "does not remove repeated images from code blocks, nested ones included" do
      code = "<pre><code>![](https://example.com/logo.png)\n\n\nend</code></pre>"
      html = %(<p><img src="/logo.png" alt=""></p>#{code}<ul><li><img src="/logo.png" alt=""></li><li>Use this:#{code}</li></ul>)
      convert(html).should == "![](https://example.com/logo.png)\n\n```\n![](https://example.com/logo.png)\n\n\nend\n```\n\n" \
                              "- Use this:\n  ```\n  ![](https://example.com/logo.png)\n\n\n  end\n  ```"
    end

    describe "in the main content" do
      def extract(html)
        Nokodown.to_markdown("<body>#{html}</body>", url: "https://example.com/dir/page", title: false)
      end

      it "drops card thumbnails beside a text link to the same page" do
        html = "<main><h1>Hiking boots</h1><ul>" \
               '<li><a href="/p/1"><img src="/1.jpg" alt="Trail boot in brown leather"></a>' \
               '<h3><a href="/p/1">Trail boot</a></h3><p>Waterproof leather for long days on rocky ground.</p></li>' \
               '<li><a href="/p/2/"><img src="/2.jpg" alt="Ridge runner"><img src="/2-hover.jpg" alt="Ridge runner, side view"></a>' \
               '<h3><a href="/p/2">Ridge runner</a></h3><p>A light mesh boot for fast summer hikes.</p></li>' \
               '<li><a href="/lookbook.jpg"><img src="/lookbook-small.jpg" alt="Boots on a mountain trail"></a></li></ul></main>'
        extract(html).should == "# Hiking boots\n\n" \
                                "- [Trail boot](https://example.com/p/1)\n  Waterproof leather for long days on rocky ground.\n" \
                                "- [Ridge runner](https://example.com/p/2)\n  A light mesh boot for fast summer hikes.\n" \
                                "- ![Boots on a mountain trail](https://example.com/lookbook-small.jpg)"
      end

      it "moves a card's list marker past a nested list of thumbnails" do
        html = "<main><h1>Hiking boots</h1><ul>" \
               '<li><ul><li><a href="/p/1"><img src="/1a.jpg" alt="Trail boot, front"></a></li>' \
               '<li><a href="/p/1"><img src="/1b.jpg" alt="Trail boot, side"></a></li></ul>' \
               '<h3><a href="/p/1">Trail boot</a></h3><p>Waterproof leather for long days on rocky ground.</p></li>' \
               '<li><ul><li><a href="/p/2"><img src="/2a.jpg" alt="Ridge runner, front"></a></li></ul>' \
               '<h3><a href="/p/2">Ridge runner</a></h3><p>A light mesh boot for fast summer hikes.</p></li></ul></main>'
        extract(html).should == "# Hiking boots\n\n" \
                                "- [Trail boot](https://example.com/p/1)\n  Waterproof leather for long days on rocky ground.\n" \
                                "- [Ridge runner](https://example.com/p/2)\n  A light mesh boot for fast summer hikes."
      end

      it "keeps a thumbnail when no link left in the Markdown names its page in words" do
        html = "<main><h1>Case studies</h1><p>How our customers ship faster with our software.</p>" \
               '<div><a href="/c/1"><img src="/1.jpg" alt="Acme warehouse floor"></a><p>Acme cut picking time in half.</p>' \
               '<a href="/c/1">Read more</a></div>' \
               '<div><a href="/c/2"><img src="/2.jpg" alt="Canvas tote bag"></a><p><a href="/c/2">$40</a></p></div>' \
               '<div><a href="/c/4"><img src="/4.jpg" alt="Harbour wall at dawn"></a><p><a href="/c/4">Oct 1, 2026</a></p></div>' \
               '<div><a href="/c/3"><img src="/3.jpg" alt="Globex conveyor belts"></a><h4><a href="/c/3">Globex</a></h4></div></main>'
        extract(html).should == "# Case studies\n\nHow our customers ship faster with our software.\n\n" \
                                "![Acme warehouse floor](https://example.com/1.jpg)\n\nAcme cut picking time in half.\n\n" \
                                "![Canvas tote bag](https://example.com/2.jpg)\n\n[$40](https://example.com/c/2)\n\n" \
                                "![Harbour wall at dawn](https://example.com/4.jpg)\n\n[Oct 1, 2026](https://example.com/c/4)\n\n" \
                                "![Globex conveyor belts](https://example.com/3.jpg)"
      end

      it "keeps article images unless a short alt repeats a text link to the same page" do
        prose = "<p>#{'Tidal lagoons release water through turbines as the tide turns. ' * 4}</p>"
        html = "<article><h1>Tidal power</h1>#{prose}" \
               '<p><a href="/media/harbour-full.jpg"><img src="/media/harbour.jpg" alt="Harbour wall at dawn"></a></p>' \
               '<p><img src="/media/turbine.jpg" alt=""></p>' \
               '<p>Next: <a href="/guide"><img src="/guide.jpg" alt="Tide guide"></a> <a href="/guide">A guide to tides</a></p>' \
               "#{prose}</article>"
        markdown = extract(html)

        markdown.should include("![Harbour wall at dawn](https://example.com/media/harbour.jpg)")
        markdown.should include("![](https://example.com/media/turbine.jpg)")
        markdown.should include("Next: [A guide to tides](https://example.com/guide)")
        markdown.should_not include("guide.jpg")
      end

      it "drops an article thumbnail whose longer alt repeats the link text, and keeps photos without alt text in any wrapper" do
        prose = "<p>#{'Tidal lagoons release water through turbines as the tide turns. ' * 4}</p>"
        html = "<article><h1>Tidal power</h1>#{prose}" \
               '<div><img src="/media/lagoon.jpg" alt=""></div>' \
               '<p>Start here: <a href="/tides"><img src="/tides.jpg" alt="Tides explained in four pictures"></a> ' \
               '<a href="/tides">Tides explained</a></p>' \
               '<p>Or: <a href="/severn"><img src="/severn.jpg" alt="Map of the Severn estuary"></a> <a href="/severn">Severn guide</a></p>' \
               "#{prose}</article>"
        markdown = extract(html)

        markdown.should include("![](https://example.com/media/lagoon.jpg)")
        markdown.should include("Start here: [Tides explained](https://example.com/tides)")
        markdown.should include("Or: ![Map of the Severn estuary](https://example.com/severn.jpg) [Severn guide](https://example.com/severn)")
      end

      it "drops images marked decorative, but not the ticks of a comparison table" do
        html = '<main><h1>Plans</h1><div class="hero"><img src="/hero.jpg" alt=""></div><p>Pick the plan that fits your team.</p>' \
               "<table><tr><th>Feature</th><th>Basic</th><th>Pro</th></tr>" \
               '<tr><td>Backups</td><td><img src="/tick.png" alt=""></td><td><img src="/tick.png" alt=""></td></tr>' \
               '<tr><td>Support</td><td><img src="/cross.png" alt=""></td><td><img src="/tick.png" alt=""></td></tr></table></main>'
        extract(html).should == "# Plans\n\nPick the plan that fits your team.\n\n| Feature | Basic | Pro |\n| --- | --- | --- |\n" \
                                "| Backups | ![](https://example.com/tick.png) | ![](https://example.com/tick.png) |\n" \
                                "| Support | ![](https://example.com/cross.png) | ![](https://example.com/tick.png) |"
      end

      it "drops what a removed image leaves as boilerplate, and escapes text it leaves at a line start" do
        html = '<main><h1>Plans</h1><p>Pick the plan that fits your team.</p><p><img src="/spinner.gif" alt=""> Loading</p>' \
               '<div><img src="/medal.png" alt=""> # 1 rated by small teams</div><div><img src="/arrow.png" alt=""> &gt; Compare plans</div></main>'
        extract(html).should == "# Plans\n\nPick the plan that fits your team.\n\n\\# 1 rated by small teams\n\n\\> Compare plans"
      end

      it "keeps article figures marked presentational and large photos marked decorative" do
        prose = "<p>#{'Memory grows each time the cache misses, so the graph below climbs steadily. ' * 4}</p>"
        figure = '<figure><img src="/leak.png" alt="" role="presentation" width="700" height="400"><figcaption>Memory leak in action</figcaption></figure>'
        extract("<article><h1>Leaks</h1>#{prose}#{figure}#{prose}</article>").should include("![](https://example.com/leak.png)\n\nMemory leak in action")
        extract('<main><h1>Kettle</h1><p>A steel kettle.</p><div><img src="/kettle.jpg" alt="" width="2000" height="2000"></div></main>').should ==
          "# Kettle\n\nA steel kettle.\n\n![](https://example.com/kettle.jpg)"
      end

      it "keeps the words around a decorative image apart" do
        extract('<main><h1>Plans</h1><p>Pick the plan that fits.</p><p>Rated<img src="/star.png" role="presentation">4.5 by teams</p></main>').should ==
          "# Plans\n\nPick the plan that fits.\n\nRated 4.5 by teams"
      end

      it "keeps an article photo whose descriptive alt only mentions a link label" do
        prose = "<p>#{'Most learners compare a few tutoring services before they commit to one. ' * 4}</p>"
        chart = '<figure><a href="https://learner.example/"><img src="/chart.png" alt="Price comparison chart of Learner and rivals"></a>' \
                "<figcaption>Prices in 2026</figcaption></figure>"
        html = "<article><h1>Tutors</h1>#{prose}#{chart}<p>We tried <a href=\"https://learner.example/\">Learner</a> first.</p>#{prose}</article>"
        extract(html).should include("![Price comparison chart of Learner and rivals](https://example.com/chart.png)")
      end

      it "keeps the headings of sections that held only decorative images" do
        html = "<main><h1>Shop software</h1><p>Everything you need to run a small shop.</p>" \
               '<h2>Why us</h2><h3>Fast</h3><div><img src="/fast.png" role="presentation"></div>' \
               '<h3>Safe</h3><div><img src="/safe.png" alt=""></div></main>'
        extract(html).should == "# Shop software\n\nEverything you need to run a small shop.\n\n## Why us\n\n### Fast\n\n### Safe"
      end
    end
  end

  describe "lists" do
    it "renders nested lists with indentation" do
      convert("<ul><li>One<ul><li>One A</li></ul></li><li>Two</li></ul>").should == "- One\n  - One A\n- Two"
    end

    it "numbers ordered lists from their start attribute" do
      convert('<ol start="3"><li>c</li><li>d</li></ol>').should == "3. c\n4. d"
    end

    it "keeps items holding several paragraphs tight, the later paragraphs indented" do
      convert("<ol><li><p>First</p><p>More</p></li><li><p>Second</p></li></ol>").should == "1. First\n   More\n2. Second"
    end

    it "writes the headings of list items as their text" do
      convert('<ul><li><h3><a href="/p/1">Trail boot</a></h3><p>Leather</p></li></ul><ol><li><h2>&gt; 1 pick</h2></li></ol>').should ==
        "- [Trail boot](https://example.com/p/1)\n  Leather\n\n1. \\> 1 pick"
    end

    it "looks through wrappers between the list and its items" do
      convert("<ul><div><li>a</li><li>b</li></div></ul>").should == "- a\n- b"
    end

    it "renders task list checkboxes" do
      convert('<ul><li><input type="checkbox" checked> Done</li><li><input type="checkbox"> Todo</li></ul>').should == "- [x] Done\n- [ ] Todo"
    end

    it "drops bullets and repeated numbers typed into items" do
      html = "<ul><li>Zero</li><li>• One</li><li>•Two</li></ul><ol><li><span>1.</span> First</li><li>2. Second</li></ol>"
      convert(html).should == "- Zero\n- One\n- Two\n\n1. First\n2. Second"
    end

    it "keeps a typed dash that only one item has and separate groups of nested lists" do
      convert("<ul><li>–5%</li><li>– 3%</li></ul>").should == "- –5%\n- – 3%"
      convert("<ul><li><ul><li>Camera</li><li>Strap</li></ul></li><li><ul><li>Lens</li><li>Cap</li></ul></li></ul>").should ==
        "- - Camera\n  - Strap\n- - Lens\n  - Cap"
    end

    it "keeps glyphs that differ between items and minus signs" do
      html = "<ul><li>● Waterproof</li><li>○ Insulated</li></ul><ul><li>- Cold</li><li>- Dry</li></ul>" \
             "<ul><li>-5 °C</li><li>-3 °C</li></ul>"
      convert(html).should == "- ● Waterproof\n- ○ Insulated\n\n- Cold\n- Dry\n\n- -5 °C\n- -3 °C"
    end

    it "keeps any markers that differ between items, as in pros and cons" do
      html = "<ul><li>+ Light</li><li>+ Cheap</li><li>- Fragile</li></ul><ul><li>✓ Fast</li><li>✗ Loud</li><li>• Big</li></ul>" \
             "<ul><li>← Previous</li><li>→ Next</li></ul>"
      convert(html).should == "- + Light\n- + Cheap\n- - Fragile\n\n- ✓ Fast\n- ✗ Loud\n- • Big\n\n- ← Previous\n- → Next"
    end

    it "keeps a run of glyphs, as in ratings" do
      convert("<ul><li>●●●○○ Comfort</li><li>●●●○○ Warmth</li></ul>").should == "- ●●●○○ Comfort\n- ●●●○○ Warmth"
    end

    it "keeps typed numbers that are not the item's own" do
      convert("<ol><li>1.5 kg flour</li><li>3. Salt</li></ol>").should == "1. 1.5 kg flour\n2. 3. Salt"
    end

    it "moves up a bulleted list that opens an item instead of printing an empty marker" do
      convert("<ul><li><ul><li>a</li><li>b</li></ul></li><li>c</li></ul>").should == "- a\n- b\n- c"
    end

    it "nests a list under the item with text before it" do
      html = "<ul><li>Parent</li><li><ul><li>Child</li></ul></li></ul>" \
             "<ul><strong>Minimum:</strong><br><ul><li>OS: Linux</li><li>Memory: 8 GB</li></ul></ul>"
      convert(html).should == "- Parent\n  - Child\n\n- **Minimum:**\n  - OS: Linux\n  - Memory: 8 GB"
    end

    it "does not join a wrapped list to an item that ends with a list" do
      convert("<ul><li>Mouse<ul><li>Quiet</li></ul></li><li><ul><li>Heavy</li></ul></li></ul>").should == "- Mouse\n  - Quiet\n- Heavy"
    end

    it "keeps an item together when content follows its nested list" do
      convert("<ul><li><ul><li>Photo</li></ul>Boot $5</li><li><ul><li>Photo</li></ul>Sock $6</li></ul>").should ==
        "- - Photo\n  Boot $5\n- - Photo\n  Sock $6"
    end

    it "keeps a numbered list nested at the start of an item under its own number" do
      convert("<ol><li><ol><li>a</li><li>b</li></ol></li><li>c</li></ol>").should == "1. 1. a\n   2. b\n2. c"
    end

    it "renders definition lists as term and definition pairs" do
      convert("<dl><dt>Weight</dt><dd>540 g</dd><dt>Colors</dt><dd>Brown</dd><dd>Black</dd></dl>").should ==
        "- **Weight**: 540 g\n- **Colors**: Brown; Black"
    end

    it "does not add a colon after a term that ends with one" do
      convert("<dl><dt>Material:</dt><dd>Leather</dd><dt>材料：</dt><dd>革</dd></dl>").should ==
        "- **Material:** Leather\n- **材料：** 革"
    end

    it "keeps a list or a table inside a definition under its term" do
      html = "<dl><dt>Colors</dt><dd><ul><li>Brown</li><li>Black</li></ul></dd>" \
             "<dt>Sizes</dt><dd><table><tr><th>S</th><th>M</th></tr><tr><td>36</td><td>38</td></tr></table></dd></dl>"
      convert(html).should == "- **Colors**\n  - Brown\n  - Black\n- **Sizes**\n  | S | M |\n  | --- | --- |\n  | 36 | 38 |"
    end

    it "keeps the paragraphs and code of a longer definition under its term" do
      html = "<dl><dt>cache(f)</dt><dd><p>Caches results.</p><pre>cache(f)(1)</pre></dd><dt>Since</dt><dd>3.9</dd></dl>"
      convert(html).should == "- **cache(f)**\n  Caches results.\n  ```\n  cache(f)(1)\n  ```\n- **Since**: 3.9"
    end
  end

  describe "code" do
    it "fences preformatted code and keeps its language" do
      convert(%(<pre><code class="language-python">def f():\n    return 1</code></pre>)).should == "```python\ndef f():\n    return 1\n```"
    end

    it "reads the language from wrappers used by GitHub and Sphinx" do
      convert('<div class="highlight-shell"><div class="highlight"><pre>ls -la</pre></div></div>').should == "```shell\nls -la\n```"
    end

    it "drops the language label and copy button printed with the code" do
      convert("<p>js</p><pre><code>let a = 1</code></pre><p>Copy</p><p>Python Copy code</p><pre>print(1)</pre><p>Output</p><pre>1</pre>").should ==
        "```js\nlet a = 1\n```\n\n```python\nprint(1)\n```\n\nOutput\n\n```\n1\n```"
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

    # Main-content cleaning sees highlighter markup, whose token classes and
    # one-word tokens look like page furniture.
    describe "in the main content" do
      def code_block(code)
        prose = "<p>#{'This example sends a request and prints the response. ' * 6}</p>"
        Nokodown.to_markdown("<body><article>#{prose}<pre>#{code}</pre></article></body>", title: false)[/```.*/m]
      end

      it "keeps tokens classed as comments or tags" do
        code_block(%(<span class="token comment">// Still "Taylor"!</span>\n<span class="token tag">&lt;div&gt;</span>)).should ==
          %(```\n// Still "Taylor"!\n<div>\n```)
      end

      it "keeps tokens that read like share or print buttons" do
        code_block('<span class="nb">print</span>(user.<span class="n">email</span>)').should == "```\nprint(user.email)\n```"
      end

      it "keeps tokens classed like page widgets" do
        code_block('curl -u <span class="tooltip"><span>API_KEY</span></span>:').should == "```\ncurl -u API_KEY:\n```"
      end
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

    it "drops horizontal rules" do
      convert("<hr><p>a</p><hr><hr><p>b</p><hr>").should == "a\n\nb"
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

    it "shortens a quote that repeats an earlier post to its opening sentence, without links" do
      post = "The stove boils a litre in three minutes on a full canister. It is a bit slower in the cold, " \
             "and the piezo lighter fails above 3000 metres, so carry matches."
      html = "<p>#{post}</p><blockquote><p><a href=\"/posts/1\">Sam said:</a></p><p>#{post}</p></blockquote><p>Same here.</p>"
      convert(html).should ==
        "#{post}\n\n> Sam said:\n>\n> The stove boils a litre in three minutes on a full canister. …\n\nSame here."
    end

    it "keeps a short quote of an earlier post whole" do
      post = "The stove boils a litre in three minutes on a full canister."
      convert("<p>#{post}</p><p>Sam posted...</p><blockquote><p>#{post}</p></blockquote><p>Mine too.</p>").should ==
        "#{post}\n\nSam posted...\n\n> #{post}\n\nMine too."
    end

    it "opens a shortened quote with the quoter's words, not the quote nested in it" do
      post = "The stove boils a litre in three minutes on a full canister, a bit slower in the cold."
      reply = "Mine takes four minutes. The wind matters more than the cold, so I always bring a windscreen along."
      html = "<p>#{post}</p><blockquote><p>#{post}</p></blockquote><p>#{reply}</p>" \
             "<blockquote><p>Ann wrote:</p><blockquote><p>#{post}</p></blockquote><p>#{reply}</p></blockquote><p>Agreed.</p>"
      convert(html).should == "#{post}\n\n> #{post}\n\n#{reply}\n\n> Ann wrote:\n>\n> #{reply} …\n\nAgreed."
    end

    it "closes the bold a shortened quote cuts through" do
      post = "The stove boils a full litre of water in three minutes on a canister. It is a bit slower in the cold, " \
             "and the piezo lighter fails above 3000 metres, so carry matches."
      convert("<p>Tip: <b>#{post}</b></p><blockquote><p>Tip: <b>#{post}</b></p></blockquote>").should ==
        "Tip: **#{post}**\n\n> Tip: **The stove boils a full litre of water in three minutes on a canister.** …"
    end

    it "keeps a quote that repeats another quote" do
      quote = "Tears after the last morning of yoga say it all. The venue was spacious and perfectly located. " \
              "The food was freshly cooked and the people were wonderful. Thank you so much for a week we will never forget."
      convert("<blockquote><p>#{quote}</p></blockquote><p>Desert yoga at sunset</p><blockquote><p>#{quote}</p></blockquote>").should ==
        "> #{quote}\n\nDesert yoga at sunset\n\n> #{quote}"
    end

    it "keeps a quote of text that is not on the page" do
      quote = "The tide is the most predictable renewable resource we have, more than wind or sun."
      convert("<p>Engineers agree.</p><blockquote><p>#{quote}</p></blockquote>").should == "Engineers agree.\n\n> #{quote}"
    end

    it "drops a section rendered a second time, but keeps a single repeated paragraph" do
      first = "The stove boils a litre in three minutes on a full canister, and a little slower in cold mountain weather."
      second = "It weighs 85 grams and folds into its own pot, so it takes almost no room at all in a pack or a bike bag."
      convert("<div><p>#{first}</p><p>#{second}</p></div><div><p>#{first}</p><p>#{second}</p></div>").should == "#{first}\n\n#{second}"
      convert("<p>#{first}</p><p>Day two.</p><p>#{first}</p>").should == "#{first}\n\nDay two.\n\n#{first}"
    end

    it "drops the placeholder a script-loaded widget leaves, and its heading" do
      convert("<p>Fits a 1 litre pot.</p><h2>Questions &amp; Answers</h2><div>Loading Questions...</div>").should == "Fits a 1 litre pot."
    end

    it "drops a trailing heading left without content" do
      convert("<h2>Intro</h2><p>Text</p><h2>Related</h2>").should == "## Intro\n\nText"
    end

    it "keeps a trailing list of linked titles" do
      html = '<h2>Candles</h2><p>3 products</p><h3><a href="/fig">Fig candle</a></h3>' \
             '<h3><a href="/pear">Pear candle</a></h3><h3><a href="/sage">Sage candle</a></h3>'
      convert(html).should == "## Candles\n\n3 products\n\n### [Fig candle](https://example.com/fig)\n\n" \
                              "### [Pear candle](https://example.com/pear)\n\n### [Sage candle](https://example.com/sage)"
    end
  end
end

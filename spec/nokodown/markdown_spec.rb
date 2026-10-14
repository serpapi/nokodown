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

    it "uses the alt text of emoji images" do
      convert('<p>Done <img class="wp-smiley" src="/e.png" alt="🎉"></p>').should == "Done 🎉"
    end

    it "drops repeated responsive variants of one image" do
      html = '<figure><img src="/a-small.jpg" alt="Harbour at dawn"><figcaption>Credit</figcaption>' \
             '<img src="/a-large.jpg" alt="Harbour at dawn"><figcaption>Credit</figcaption></figure>'
      convert(html).should == "![Harbour at dawn](https://example.com/a-small.jpg)\n\nCredit"
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

    it "does not remove repeated images from code blocks, nested ones included" do
      code = "<pre><code>![](https://example.com/logo.png)\n\n\nend</code></pre>"
      html = %(<p><img src="/logo.png" alt=""></p>#{code}<ul><li><img src="/logo.png" alt=""></li><li>Use this:#{code}</li></ul>)
      convert(html).should == "![](https://example.com/logo.png)\n\n```\n![](https://example.com/logo.png)\n\n\nend\n```\n\n" \
                              "- Use this:\n\n  ```\n  ![](https://example.com/logo.png)\n\n\n  end\n  ```"
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
                                "- ### [Trail boot](https://example.com/p/1)\n\n  Waterproof leather for long days on rocky ground.\n\n" \
                                "- ### [Ridge runner](https://example.com/p/2)\n\n  A light mesh boot for fast summer hikes.\n\n" \
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
                                "- ### [Trail boot](https://example.com/p/1)\n\n  Waterproof leather for long days on rocky ground.\n\n" \
                                "- ### [Ridge runner](https://example.com/p/2)\n\n  A light mesh boot for fast summer hikes."
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

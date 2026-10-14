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

    it "writes raised cents after a price as decimals" do
      html = "<p>$549<sup>99</sup>, <span>$2,799</span><sup>00</sup>, <sup>$</sup>19<sup>95</sup>, the 10<sup>15</sup> scale</p>"
      convert(html).should == "$549.99, $2,799.00, $19.95, the 10¹⁵ scale"
    end

    it "keeps French and wrapped ordinals as text and uses the characters for raised o and TM" do
      html = "<p>le 1<sup>er</sup> mai, le XIX<sup>e</sup> siècle, the 21<span><sup>st</sup></span>, " \
             "1<sup>o</sup> piso, 30<sup>o</sup>C, Acme<sup>TM</sup></p>"
      convert(html).should == "le 1er mai, le XIXe siècle, the 21st, 1º piso, 30ºC, Acme™"
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

    it "drops bullets and repeated numbers typed into items" do
      html = "<ul><li>Zero</li><li>• One</li><li>•Two</li></ul><ol><li><span>1.</span> First</li><li>2. Second</li></ol>"
      convert(html).should == "- Zero\n- One\n- Two\n\n1. First\n2. Second"
    end

    it "keeps glyphs that differ between items and minus signs" do
      html = "<ul><li>● Waterproof</li><li>○ Insulated</li></ul><ul><li>- Cold</li><li>- Dry</li></ul>" \
             "<ul><li>-5 °C</li><li>-3 °C</li></ul>"
      convert(html).should == "- ● Waterproof\n- ○ Insulated\n\n- Cold\n- Dry\n\n- -5 °C\n- -3 °C"
    end

    it "keeps typed numbers that are not the item's own" do
      convert("<ol><li>1.5 kg flour</li><li>3. Salt</li></ol>").should == "1. 1.5 kg flour\n2. 3. Salt"
    end

    it "moves up a bulleted list that opens an item instead of printing an empty marker" do
      convert("<ul><li><ul><li>a</li><li>b</li></ul></li><li>c</li></ul>").should == "- a\n- b\n- c"
    end

    it "keeps an item together when content follows its nested list" do
      convert("<ul><li><ul><li>Photo</li></ul>Boot $5</li><li><ul><li>Photo</li></ul>Sock $6</li></ul>").should ==
        "- - Photo\n\n  Boot $5\n\n- - Photo\n\n  Sock $6"
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
      convert(html).should == "- **Colors**\n  - Brown\n  - Black\n\n- **Sizes**\n\n  | S | M |\n  | --- | --- |\n  | 36 | 38 |"
    end

    it "keeps the paragraphs and code of a longer definition under its term" do
      html = "<dl><dt>cache(f)</dt><dd><p>Caches results.</p><pre>cache(f)(1)</pre></dd><dt>Since</dt><dd>3.9</dd></dl>"
      convert(html).should == "- **cache(f)**\n\n  Caches results.\n\n  ```\n  cache(f)(1)\n  ```\n\n- **Since**: 3.9"
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

# frozen_string_literal: true

RSpec.describe Nokodown do
  describe ".extract" do
    it "returns the markdown with the page metadata" do
      result = Nokodown.extract(fixture("article.html"), url: "https://example.com/tidal")

      result.markdown.should start_with("# How Tidal Power Plants Store Energy\n\nTidal lagoons hold water")
      result.title.should == "How Tidal Power Plants Store Energy"
      result.byline.should == "Mara Lindqvist"
      result.excerpt.should == "Lagoons, barrages and turbines that run in both directions."
      result.site_name.should == "Coastal Engineering Weekly"
      result.published_time.should == "2026-09-30T08:00:00Z"
      result.lang.should == "en"
      result.mode.should == :article
    end

    it "returns empty markdown for an empty document" do
      Nokodown.extract("").markdown.should == ""
    end

    it "reports :none for a frameset page, which has no body" do
      result = Nokodown.extract('<html><head><title>Frames</title></head><frameset><frame src="a.html"></frameset></html>')

      result.mode.should == :none
      result.markdown.should == ""
      result.title.should == "Frames"
    end

    it "accepts nil" do
      Nokodown.extract(nil).markdown.should == ""
    end

    it "falls back to the first paragraph for the excerpt" do
      html = "<title>Notes</title><p>Short.</p><p>#{'A sentence long enough to describe the page. ' * 3}</p>"

      Nokodown.extract(html).excerpt.should start_with("A sentence long enough")
    end
  end

  describe ".to_markdown" do
    it "returns just the markdown" do
      Nokodown.to_markdown("<title>Hello</title><p>World</p>").should == "# Hello\n\nWorld"
    end
  end

  describe "cleanup of the main content" do
    def extract(html)
      Nokodown.to_markdown(html, url: "https://example.com/page", title: false)
    end

    let(:prose) { "<p>#{'The command line tool runs on every major platform and needs nothing else to work. ' * 3}</p>" }

    it "keeps the link lists of an index page, which are its content" do
      sections = { "A" => %w[Anatomy Astronomy Architecture], "B" => %w[Biology Botany Banking], "C" => %w[Chemistry Climate Cooking] }
      html = sections.map do |letter, topics|
        "<h2>#{letter}</h2><ul>#{topics.map { |topic| "<li><a href=\"/topics/#{topic.downcase}\">#{topic}</a></li>" }.join}</ul>"
      end.join

      markdown = extract("<main><h1>Topics A-Z</h1>#{html}</main>")

      markdown.should include("## A\n\n- [Anatomy](https://example.com/topics/anatomy)")
      markdown.should include("- [Cooking](https://example.com/topics/cooking)")
    end

    it "drops the cart controls of product cards and the links beside them" do
      categories = '<div><a href="/c/cups">Cups</a> <a href="/c/jugs">Jugs</a> <a href="/c/bowls">Bowls</a></div>'
      card = '<li><a href="/p/mug"><img src="/mug.jpg" alt="Stoneware mug"><h2>Stoneware mug</h2></a><span>$18</span>' \
             '<div class="actions"><a class="button" href="/cart/add?id=1">Add to cart</a> <span>Quick view</span></div></li>'

      markdown = extract("<main><h1>Mugs</h1>#{categories}<ul>#{card * 3}</ul></main>")

      markdown.should include("## [Stoneware mug](https://example.com/p/mug)\n\n  $18")
      ["Cups", "Add to cart", "Quick view"].each { |noise| markdown.should_not include(noise) }
    end

    it "drops links styled as buttons" do
      html = "<article>#{prose}<div><a class=\"btn btn-primary\" href=\"/signup\">Sign up now</a> " \
             "<a class=\"btn\" href=\"/demo\">Book a demo</a></div>#{prose}</article>"

      markdown = extract(html)

      markdown.should_not include("Sign up now")
      markdown.should_not include("Book a demo")
    end

    it "keeps a button inside a sentence, FAQ toggles and buttons in data tables" do
      html = <<~HTML
        <article>#{prose}
          <p>Use the <a class="btn btn-sm" href="/download">Download</a> button to get the installer for your system.</p>
          <h2><a role="button" aria-expanded="false" href="#offline">Does it work offline?</a></h2>
          <div id="offline">#{prose}</div>
          <table><tr><th>Plan</th><th>Price</th><th>Order</th></tr><tr><td>Solo</td><td>$5</td><td><a class="btn" href="/buy">Buy</a></td></tr></table>
        </article>
      HTML

      markdown = extract(html)

      markdown.should include("Use the [Download](https://example.com/download) button")
      markdown.should include("## Does it work offline?")
      markdown.should include("| Solo | $5 | [Buy](https://example.com/buy) |")
    end

    it "keeps highlighted code whose tokens look like page furniture" do
      html = "<article>#{prose}<pre><code class=\"language-python\"><span class=\"nb\">print</span>(x)</code></pre>#{prose}</article>"

      extract(html).should include("```python\nprint(x)\n```")
    end
  end

  describe "main_content: false" do
    it "keeps navigation, headers and footers" do
      markdown = Nokodown.to_markdown(fixture("article.html"), url: "https://example.com/", main_content: false)

      markdown.should include("[News](https://example.com/news)")
      markdown.should include("3 comments")
      markdown.should include("Tidal lagoons hold water")
    end

    it "still drops scripts, hidden elements and form controls" do
      html = "<p>Visible</p><script>alert(1)</script><p hidden>Hidden</p><div style='display: none'>Gone</div><input value='x'>"

      Nokodown.extract(html, main_content: false, title: false).markdown.should == "Visible"
    end

    it "reports :full mode" do
      Nokodown.extract("<p>x</p>", main_content: false).mode.should == :full
    end
  end

  describe "title: false" do
    it "does not prepend the metadata title" do
      markdown = Nokodown.to_markdown(fixture("article.html"), title: false)

      markdown.should start_with("Tidal lagoons hold water")
    end
  end

  describe "images: false" do
    it "drops images but keeps emoji" do
      markdown = convert('<p><img src="/a.png" alt="Chart"> Done <img class="emoji" alt="✅" src="/e.png"></p>', images: false)

      markdown.should == "Done ✅"
    end
  end

  describe "links: false" do
    it "keeps link text only" do
      convert('<p>Read <a href="/docs">the docs</a>.</p>', links: false).should == "Read the docs."
    end
  end

  describe "encodings" do
    it "transcodes binary input using the declared charset" do
      html = "<html><head><meta charset=\"windows-1252\"></head><body><p>caf\xE9</p></body></html>".b

      Nokodown.to_markdown(html, title: false).should == "café"
    end

    it "drops invalid UTF-8 bytes" do
      Nokodown.to_markdown("<p>a\xFFb</p>", title: false).should == "ab"
    end
  end
end

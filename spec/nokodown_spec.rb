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

    it "returns empty markdown, but the title, when the page has no content" do
      result = Nokodown.extract('<title>Dashboard</title><body><div id="app"></div><script src="/app.js"></script></body>')

      result.markdown.should == ""
      result.title.should == "Dashboard"
    end

    it "keeps the headline of a page that has nothing else" do
      html = "<title>Harbour Town Community Forum</title><body><h1>Is the ferry running today?</h1></body>"

      Nokodown.to_markdown(html).should == "# Is the ferry running today?"
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

  describe "accordions and tabs" do
    def article(widget)
      Nokodown.to_markdown("<title>Trail stove</title><article><h1>Trail stove</h1><p>#{'It boils a litre in three minutes. ' * 6}</p>#{widget}</article>")
    end

    it "keeps a closed accordion panel that a button opens" do
      html = '<button aria-controls="faq-1" aria-expanded="false">Do you ship abroad?</button>' \
             '<div id="faq-1" class="accordion-panel" aria-hidden="true"><p>Yes, to most of Europe.</p></div>'

      convert(html).should == "Do you ship abroad?\n\nYes, to most of Europe."
    end

    it "keeps a closed tab panel labelled by its tab" do
      convert('<div role="tabpanel" aria-labelledby="tab-2" aria-hidden="true"><p>Weighs 85 g.</p></div>').should == "Weighs 85 g."
    end

    it "drops aria-hidden icons and the full copy behind a read-more link" do
      html = '<p><span class="icon" aria-hidden="true">★</span> Used, with light wear on the ... ' \
             '<span class="expandable-text" aria-hidden="true">Used, with light wear on the cover.</span></p>'

      convert(html).should == "Used, with light wear on the ..."
    end

    it "drops a strip of tab labels" do
      article('<ul role="tablist"><li role="tab">Specifications</li><li role="tab">Reviews</li></ul>').should_not include("Specifications")
    end

    it "keeps a tab list wrapped around its panels" do
      markdown = article('<div role="tablist"><ul><li role="tab">Specifications</li></ul><div role="tabpanel"><p>Weighs 85 g.</p></div></div>')

      markdown.should include("Weighs 85 g.")
    end

    it "keeps an FAQ marked up as a tab list" do
      answer = "No. It only takes screw-on canisters of isobutane and propane, sold at most outdoor shops. " * 3
      markdown = article("<div role='tablist'><h2>Can it burn white gas?</h2><p>#{answer}</p></div>")

      markdown.should include("## Can it burn white gas?\n\nNo. It only takes")
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

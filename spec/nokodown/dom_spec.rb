# frozen_string_literal: true

RSpec.describe Nokodown::Dom do
  def element(attributes)
    Nokolexbor::HTML("<div #{attributes}></div>").at_css("div")
  end

  describe ".paragraph_keys" do
    def keyed(html)
      body = Nokolexbor::HTML("<body>#{html}</body>").at_css("body")
      described_class.assign_keys(body)
      body
    end

    def paragraphs(body, root = body)
      keys = described_class.paragraph_keys(root)
      body.css("[id]").select { |node| keys.include?(described_class.key(node)) }.map { |node| node["id"] }
    end

    it "finds paragraphs and the divs without block children Readability rewrites into them" do
      body = keyed(<<~HTML)
        <div id="outer"><div id="text">Plain <b>text</b></div><p id="para">Para <span>graph</span></p>
        <div id="list"><ul><li>Item</li></ul></div><div id="picture"><span><img src="a.jpg"></span></div><section id="section">Text</section></div>
      HTML

      paragraphs(body).should == %w[text para]
      paragraphs(body, body.at_css("#text")).should == %w[text]
    end

    # Lexbor copies a link that is cut by a block into several elements that
    # share one attribute list, so the copies share a key too.
    it "does not take a div with a block in a misnested link for a paragraph" do
      body = keyed('<div id="wrapper"><a href="/cart"><div>Offer</div><footer><span>Sale</span></a></footer></div>')

      paragraphs(body).should == []
    end
  end

  describe ".ancestors_named" do
    it "lists the ancestors with the given names, nearest first" do
      doc = Nokolexbor::HTML("<table><tr><td><div><p><b>Cell</b></p></div></td></tr></table>")

      described_class.ancestors_named(doc.at_css("b"), "td", "p", "table").map(&:name).should == %w[p td table]
      described_class.ancestors_named(doc.at_css("b"), "figure").should == []
    end

    it "climbs out of a copy or a fragment without failing" do
      doc = Nokolexbor::HTML("<figure><p><b>Cell</b></p></figure>")
      copy = doc.at_css("p").dup

      described_class.ancestors_named(copy.at_css("b"), "p", "figure").map(&:name).should == %w[p]
      described_class.ancestors_named(doc.fragment("<i><b>x</b></i>").at_css("b"), "i").map(&:name).should == %w[i]
    end
  end

  describe ".signature" do
    it "lowercases class and id and splits camelCase" do
      described_class.signature(element('class="adContainer siteNav2Bar" id="mainHeader"')).should ==
        "ad-container site-nav2-bar main-header"
    end

    it "drops generated ids and CSS module hashes" do
      node = element('class="w-node-b5343ad4-1c2e-ad12-9f0b-3c4d5e6f7a8b mdx-table_root__adKqa"')
      described_class.signature(node).should == "w-node-  mdx-table_root "
    end

    it "is empty without class and id" do
      described_class.signature(element('title="x"')).should == ""
    end

    it "gives the same signature from the cache an extraction keeps" do
      nodes = %w[adContainer adContainer cookieBanner].map { |name| element("class=\"#{name}\" id=\"x#{name}\"") }
      uncached = nodes.map { |node| described_class.signature(node) }

      cached = described_class.caching_signatures do
        Array.new(2) { nodes.map { |node| described_class.signature(node) } }
      end

      cached.should == [uncached, uncached]
      Thread.current[described_class::SIGNATURES].should be_nil
    end
  end
end

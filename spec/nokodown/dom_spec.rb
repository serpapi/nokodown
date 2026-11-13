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

    it "finds the breakers and candidates with XPath" do
      body = keyed('<div id="outer"><section><p id="sp">x</p><div id="sd">y<ol><li>z</li></ol></div></section>' \
                   '<figure><div id="cap">Caption</div><img src="a.jpg"></figure><blockquote><div id="q">Q</div></blockquote></div>')
      root = body.at_css("#outer")
      root.should_not_receive(:css)

      paragraphs(body, root).should == %w[sp cap q]
    end

    # Lexbor copies a link that is cut by a block into several elements that
    # share one attribute list, so the copies share a key too. The copy
    # visited last in a bottom-up pass decides, as it always has.
    it "lets the last copy of a misnested link decide whether it holds a block" do
      paragraphs(keyed('<div id="wrapper"><a href="/cart"><div>Offer</div><footer><span>Sale</span></a></footer></div>')).should ==
        %w[wrapper]
      paragraphs(keyed('<div id="wrapper"><a href="/cart"><span>Offer</span><footer><div>Sale</div></a></footer></div>')).should == []
    end
  end

  describe ".elements" do
    it "lists the elements under a root in document order, as css(\"*\") does" do
      html = <<~HTML
        <body><main><h1>Title</h1>text<!-- note --><section><p>One <b>bold</b> <i>two</i></p><ul><li>a</li><li><a>b</a></li></ul></section></main><footer><p>End</p></footer></body>
      HTML
      body = Nokolexbor::HTML(html).at_css("body")

      described_class.elements(body).map(&:name).should == body.css("*").map(&:name)
      described_class.elements(body.at_css("section")).map(&:name).should == %w[p b i ul li li a]
      described_class.elements(body.at_css("b")).should == []
    end

    # Copies of a formatting element a block cuts share one attribute list
    # in Lexbor; the walk must still visit each copy.
    it "visits every copy of a misnested formatting element" do
      body = Nokolexbor::HTML('<body><a href="/cart"><span>Offer</span><footer><div>Sale</div></a></footer><p>C</p></body>').at_css("body")

      described_class.assign_keys(body)
      described_class.shared_keys?(body).should == true

      described_class.elements(body).map(&:name).should == body.css("*").map(&:name)
    end

    it "keys every element in document order" do
      body = Nokolexbor::HTML("<body><div><p>x</p><p><b>y</b></p></div><p>z</p></body>").at_css("body")
      described_class.assign_keys(body)

      body.css("*").map { |node| described_class.key(node) }.should == %w[1 2 3 4 5]
    end
  end

  describe ".children" do
    it "lists a node's children with text, comments and templates, as children does" do
      html = "<body><main>One <b>bold</b><!-- note --><template><i>t</i></template><svg><title>s</title></svg>" \
             "<a href=\"/x\"><p>Block</p></a><pre>\n code</pre></main><p>End</p></body>"
      body = Nokolexbor::HTML(html).at_css("body")

      [body, body.at_css("main"), body.at_css("template"), body.at_css("svg"), body.at_css("b"), body.at_css("pre")].each do |node|
        described_class.children(node).should == node.children.to_a
      end
      described_class.children(body.at_css("main")).map(&:name).should == %w[#text b #comment template svg a pre]
      described_class.children(body.at_css("main b").child).should == []
    end
  end

  describe ".element_children" do
    it "lists a node's element children, as element_children does" do
      html = "<body><main>One <b>bold</b><!-- note --><template><i>t</i></template><svg><title>s</title></svg>" \
             "<a href=\"/x\"><p>Block</p></a> tail</main><p>End</p></body>"
      body = Nokolexbor::HTML(html).at_css("body")

      [body, body.at_css("main"), body.at_css("template"), body.at_css("svg"), body.at_css("a"), body.at_css("b")].each do |node|
        described_class.element_children(node).should == node.element_children.to_a
      end
      described_class.element_children(body.at_css("main")).map(&:name).should == %w[b template svg a]
      described_class.element_children(body.at_css("main b")).should == []
    end
  end

  describe ".spaces_to_blanks" do
    it "turns every Unicode space into a blank, as tr over the characters does" do
      characters = (0..0x10FFFF).reject { |code| code.between?(0xD800, 0xDFFF) }.map { |code| code.chr(Encoding::UTF_8) }
      [characters.join, characters.join("é"), "a\u00A0b\u3000c\u2028\u0085", "plain\ttext\n"].each do |string|
        blanked = described_class.spaces_to_blanks(string)
        blanked.should == string.tr(described_class::UNICODE_SPACES, " ")
        blanked.encoding.should == Encoding::UTF_8
      end
    end

    it "leaves invalid bytes and other encodings to tr, which raises" do
      invalid = "a\u00A0b\xFF\tc".dup.force_encoding(Encoding::UTF_8)
      latin = "a\u00A0b\tc".encode(Encoding::ISO_8859_1)
      [[invalid, ArgumentError], [latin, Encoding::CompatibilityError]].each do |string, error|
        -> { string.tr(described_class::UNICODE_SPACES, " ") }.should raise_error(error)
        -> { described_class.spaces_to_blanks(string) }.should raise_error(error)
      end
    end
  end

  describe ".min_text_length" do
    it "never exceeds the length of the squished text" do
      strings = ["", " ", "a", " a  b ", "a\0", "\0a\0 ", "a\v\fb\r\n", "a\u00A0\u00A0b", "\u3000\u2003x\u2028y\u0085",
                 "é \u00A0 ü\0", "tab\tand\nline", "\u200Bzero width\u200B", "a\u2000-\u200Ab"]
      strings.each do |string|
        described_class.min_text_length(string).should <= described_class.squish(string).length
      end
      described_class.min_text_length(" one two ").should == 6
    end
  end

  describe ".elements_bottom_up" do
    def traversed(root)
      found = []
      root.traverse { |node| found << node if node.element? }
      found
    end

    it "lists root and its elements children first, as traverse yields them" do
      body = Nokolexbor::HTML("<body><main><h1>Title</h1>text<!-- note --><section><p>One <b>bold</b></p><ul><li>a</li></ul></section></main><p>End</p></body>").at_css("body")

      described_class.elements_bottom_up(body).map(&:name).should == %w[h1 b p li ul section main p body]
      described_class.elements_bottom_up(body).map(&:name).should == traversed(body).map(&:name)
      described_class.elements_bottom_up(body.at_css("b")).map(&:name).should == %w[b]
    end

    it "visits every copy of a misnested formatting element" do
      body = Nokolexbor::HTML('<body><a href="/cart"><span>Offer</span><footer><div>Sale</div></a></footer><p>C</p></body>').at_css("body")
      described_class.assign_keys(body)
      described_class.shared_keys?(body).should == true

      described_class.elements_bottom_up(body).map { |node| [node.name, described_class.key(node)] }
        .should == traversed(body).map { |node| [node.name, described_class.key(node)] }
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

    it "finds a cached signature without building the string it is made from" do
      node = element('class="adContainer siteNav" id="mainHeader"')
      described_class.caching_signatures do
        described_class.signature(node)
        before = GC.stat(:total_allocated_objects)
        10.times { described_class.signature(node) }
        # Reading the class and the id are the only allocations left.
        (GC.stat(:total_allocated_objects) - before).should <= 20
      end
    end

    it "answers secondary? from the cache as the pattern does, and drops the cache after" do
      nodes = ["comments", "comments", "post-body", "most-read", "most-read x", "related"].map { |name| element("class=\"#{name}\"") }
      nodes << element('id="comments"') << element("")
      uncached = nodes.map { |node| Nokodown::Patterns.secondary?(described_class.signature(node)) }

      cached = described_class.caching_signatures do
        Array.new(2) { nodes.map { |node| described_class.secondary?(node) } }
      end

      uncached.should == [true, true, false, true, true, false, true, false]
      cached.should == [uncached, uncached]
      nodes.map { |node| described_class.secondary?(node) }.should == uncached
      Thread.current[described_class::SECONDARY].should be_nil
    end
  end
end

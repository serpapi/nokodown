# frozen_string_literal: true

RSpec.describe Nokodown::Stats do
  def body(html)
    node = Nokolexbor::HTML("<html><body>#{html}</body></html>").at_css("body")
    Nokodown::Dom.assign_keys(node)
    node
  end

  it "counts characters, link characters and their share for every element" do
    root = body('<div><p>Coffee beans <a href="/roast">roasted dark</a></p><p><a href="#notes">Notes</a> here</p></div>')
    stats = described_class.new(root)
    first, second = root.css("p").to_a

    [stats.chars(first), stats.link_chars(first), stats.text_chars(first)].should == [22.0, 11.0, 11.0]
    stats.link_density(first).should == 11.0 / 22
    [stats.chars(second), stats.link_chars(second)].should == [9.0, 5 * 0.3]
    stats.text_chars(root).should == 31.0 - 11.0 - 1.5
    stats.link_density(root.at_css("div")).should == 12.5 / 31
  end

  it "measures an element outside the root on demand, inside the link around it" do
    page = body('<main><p>Text</p></main><a href="/elsewhere"><span>Linked words</span></a><div></div>')
    stats = described_class.new(page.at_css("main"))

    [stats.chars(page.at_css("span")), stats.link_chars(page.at_css("span"))].should == [11.0, 11.0]
    stats.text_chars(page.at_css("span")).should == 0.0
    stats.link_density(page.at_css("div")).should == 0.0
  end

  it "tells text from elements by node type, without the predicates" do
    root = body('<div>Coffee <b>beans</b><!-- note --><a href="/roast">dark</a></div>')
    %i[text? cdata? element?].each { |name| Nokolexbor::Node.any_instance.should_not_receive(name) }

    stats = described_class.new(root)
    [stats.chars(root), stats.link_chars(root)].should == [15.0, 4.0]
  end

  it "reads an element's counts with one key lookup" do
    root = body('<p>Coffee beans <a href="/roast">roasted dark</a></p>')
    stats = described_class.new(root)
    paragraph = root.at_css("p")

    Nokodown::Dom.should_receive(:key).twice.and_call_original
    stats.text_chars(paragraph).should == 11.0
    stats.link_density(paragraph).should == 0.5
  end

  it "counts an element without a key when asked, and stores nothing under a key for it" do
    root = body('<div><p>Coffee <a href="/roast">roasted <b>dark</b></a></p></div>')
    stats = described_class.new(root)
    bold = root.at_css("b")
    bold.remove_attribute(Nokodown::Dom::KEY)
    stored = stats.instance_variable_get(:@counts).dup

    [stats.chars(bold), stats.link_chars(bold), stats.text_chars(bold), stats.link_density(bold)].should == [4.0, 4.0, 0.0, 1.0]
    stats.instance_variable_get(:@counts).should == stored
    bold.add_child("er")
    stats.forget_keyless.should equal(stats)
    stats.chars(bold).should == 6.0
  end

  it "counts an element without a key once, however often it or an element around it is asked about" do
    root = body("<p>Intro <b><span>s1</span> <span>s2</span> <span>s3</span> <span>s4</span> <span>s5</span> <span>s6</span> <span>s7</span> <span>s8</span> <span>s9</span> <span>s10</span> <span>s11</span> <span>s12</span> <span>s13</span> <span>s14</span> <span>s15</span> <span>s16</span> <span>s17</span> <span>s18</span> <span>s19</span> <span>s20</span> <span>s21</span> <span>s22</span> <span>s23</span> <span>s24</span> <span>s25</span> <span>s26</span> <span>s27</span> <span>s28</span> <span>s29</span> <span>s30</span> <span>s31</span> <span>s32</span> <span>s33</span> <span>s34</span> <span>s35</span> <span>s36</span> <span>s37</span> <span>s38</span> <span>s39</span> <span>s40</span> <span>s41</span> <span>s42</span> <span>s43</span> <span>s44</span> <span>s45</span> <span>s46</span> <span>s47</span> <span>s48</span> <span>s49</span> <span>s50</span></b></p>")
    stats = described_class.new(root)
    bold = root.at_css("b")
    paragraph = root.at_css("p")
    [bold, paragraph].each { |node| node.remove_attribute(Nokodown::Dom::KEY) }
    counted = 0
    Nokodown::Dom.stub(:char_count).and_wrap_original { |original, text| counted += 1; original.call(text) }

    root.css("span").each { |span| stats.chars(span.parent) }
    3.times { stats.text_chars(paragraph) }

    counted.should < 120
    [stats.chars(paragraph), stats.chars(bold)].should == [5.0 + 141.0, 141.0]
  end

  it "tells apart elements without a key that the parser made at the same point" do
    # The parser reopens <b> and <i> together at the second <p>.
    root = body('<p>One <b class="x"><i class="y">two</p><p>three</i> four four</p>')
    stats = described_class.new(root)
    bold, italic = root.css("p")[1].css("b, i").to_a
    bold.source_location.should == italic.source_location
    [bold, italic].each { |node| node.remove_attribute(Nokodown::Dom::KEY) }

    [stats.chars(italic), stats.chars(bold), stats.chars(italic)].should == [5.0, 13.0, 5.0]
  end

  it "finds an element without a key among a bounded few that share its place" do
    # Positions restart in every fragment the page parses, as for each
    # <noscript>, so these share a parent and a position.
    root = body("<div></div>")
    160.times { |i| root.at_css("div").add_child(root.document.fragment("<b>reply #{i}</b>")) }
    Nokodown::Dom.assign_keys(root)
    bolds = root.css("b").to_a
    bolds.map(&:source_location).uniq.size.should == 1
    bolds.each { |bold| bold.remove_attribute(Nokodown::Dom::KEY) }
    stats = described_class.new(root)
    compared = 0
    bolds.each { |bold| bold.define_singleton_method(:==) { |other| compared += 1; super(other) } }

    2.times { bolds.map { |bold| stats.chars(bold) }.should == [6.0] * 10 + [7.0] * 90 + [8.0] * 60 }
    # A lookup compares at most the HELD it last asked about, three beside
    # the one last found at the place, and one run of FINE there.
    compared.should <= 2 * bolds.size * (described_class::HELD + 3 + described_class::Listed::FINE)
  end

  it "keeps an element without a key held while elements from other places at its position are asked about" do
    # Elements from parsed fragments can share its source position, as below.
    root = body("<p>Q <b>bold</b></p>")
    bold = root.at_css("b")
    spans = Array.new(20) do
      span = bold.add_child("<span></span>").first
      17.times { span.add_child(root.document.fragment("#{" " * (bold.source_location - 1)}<b>x</b>")) }
      span
    end
    Nokodown::Dom.assign_keys(root)
    others = root.css("span b").to_a
    others.map(&:source_location).uniq.should == [bold.source_location]
    [bold, *others].each { |node| node.remove_attribute(Nokodown::Dom::KEY) }
    stats = described_class.new(root)
    counted = 0
    Nokodown::Dom.stub(:char_count).and_wrap_original { |original, text| counted += 1; original.call(text) }

    spans.each { |span| [stats.chars(bold), *span.css("b").map { |other| stats.chars(other) }].should == [344.0] + [1.0] * 17 }
    # The bold holds 681 text nodes; counting it again for every span would
    # take 20 times that.
    counted.should < 1_300
  end

  it "counts once each of many elements without a key at one place, asked about in turn" do
    # Sibling fragments put these at one place: the div's key, nothing
    # between, and one position.
    root = body("<div></div>")
    spans = (1..30).map { |i| "<span>w#{i}</span>" }.join
    20.times { root.at_css("div").add_child(root.document.fragment("<b>#{spans}</b>")) }
    Nokodown::Dom.assign_keys(root)
    bolds = root.css("b").to_a
    bolds.map(&:source_location).uniq.size.should == 1
    bolds.each { |bold| bold.remove_attribute(Nokodown::Dom::KEY) }
    stats = described_class.new(root)
    counted = 0
    Nokodown::Dom.stub(:char_count).and_wrap_original { |original, text| counted += 1; original.call(text) }

    3.times { bolds.map { |bold| stats.chars(bold) }.should == [81.0] * 20 }
    # Counting every bold again in each round would take 1,800.
    counted.should < 900
  end

  it "counts once each of many elements without a key at one place, with nothing keyed near them" do
    # Sixty-four elements without a key before each bold leave nothing
    # keyed near to tell the bolds apart by.
    root = body("<div></div>")
    spans = (1..30).map { |i| "<span>w#{i}</span>" }.join
    40.times { root.at_css("div").add_child(root.document.fragment("#{'<i></i>' * 64}<b>#{spans}</b>")) }
    Nokodown::Dom.assign_keys(root)
    bolds = root.css("b").to_a
    bolds.map(&:source_location).uniq.size.should == 1
    root.css("i, b").each { |node| node.remove_attribute(Nokodown::Dom::KEY) }
    stats = described_class.new(root)
    counted = 0
    Nokodown::Dom.stub(:char_count).and_wrap_original { |original, text| counted += 1; original.call(text) }

    3.times { bolds.map { |bold| stats.chars(bold) }.should == [81.0] * 40 }
    # Counting every bold again in each round would take 3,600.
    counted.should < 1_800
  end

  it "finds each of many elements without a key at one place without walking the tree around them" do
    # Nothing keyed lies near the bolds, and each has thousands of
    # siblings before it, so telling them apart by anything the tree would
    # have to work out, such as their path, would walk those every time.
    root = body("<div></div>")
    spans = (1..30).map { |i| "<span>w#{i}</span>" }.join
    2_000.times { root.at_css("div").add_child(root.document.fragment("#{'<i></i>' * 64}<b>#{spans}</b>")) }
    Nokodown::Dom.assign_keys(root)
    bolds = root.css("b").to_a
    # Read from the tree in one pass: css("i") takes seconds here.
    Nokodown::Dom.elements(root).each { |node| node.remove_attribute(Nokodown::Dom::KEY) if %w[i b].include?(node.name) }
    stats = described_class.new(root)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    3.times { bolds.map { |bold| stats.chars(bold) }.uniq.should == [81.0] }
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).should < 0.5
  end

  it "weighs a link without a key by its own href, as the walk from the root does" do
    root = body('<p><a href="/roast">Dark</a> <a href="#notes">Notes</a></p>')
    stats = described_class.new(root)
    roast, notes = root.css("a").to_a
    before = [roast, notes].map { |link| [stats.chars(link), stats.link_chars(link)] }
    [roast, notes].each { |link| link.remove_attribute(Nokodown::Dom::KEY) }

    [roast, notes].map { |link| [stats.chars(link), stats.link_chars(link)] }.should == before
    before.should == [[4.0, 4.0], [5.0, 5 * 0.3]]
  end

  describe "#remove" do
    def counts(stats)
      stats.instance_variable_get(:@counts)
    end

    it "removes nodes and leaves the counts a new Stats would make" do
      root = body('<div><p>Coffee <a href="/roast">roasted <b>dark</b> <i>x</i></a></p><nav>Menu items</nav>' \
                  '<a href="#n"><span>Note</span> <em>skip</em></a></div><p>Tail</p>')
      stats = described_class.new(root)
      stats.remove([root.at_css("i"), root.at_css("nav"), root.at_css("em")]).should equal(stats)

      fresh = counts(described_class.new(root))
      counts(stats).values_at(*fresh.keys).should == fresh.values
      [stats.chars(root), stats.link_chars(root)].should == [25.0, 11.0 + 4 * 0.3]
    end

    it "measures the whole root again when copies of an element share a key" do
      root = body('<a href="/cart"><span>Offer</span><footer><div>Sale</div><p>Gone</p></a></footer><p>Coffee</p>')
      stats = described_class.new(root)
      stats.remove([root.css("p").first])

      fresh = counts(described_class.new(root))
      counts(stats).should == fresh
    end

    it "stops a walk up from a removed node at an ancestor already cleared" do
      root = body("#{"<div>" * 30}<p>Text</p>#{"<nav>Menu</nav>" * 200}#{"</div>" * 30}")
      stats = described_class.new(root)
      asked = 0
      Nokodown::Dom.stub(:key).and_wrap_original { |original, node| asked += 1; original.call(node) }
      stats.remove(root.css("nav").to_a)

      asked.should < 400
      [stats.chars(root), stats.link_chars(root)].should == [4.0, 0.0]
    end
  end

  it "is made once for the page when Boilerplate removes no member panel" do
    described_class.should_receive(:new).once.and_call_original
    Nokodown.to_markdown("<body><nav><a href='/'>Home</a></nav><article><p>#{'Coffee is brewed from roasted beans. ' * 20}</p></article></body>")
  end
end

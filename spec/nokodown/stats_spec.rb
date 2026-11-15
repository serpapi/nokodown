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

  it "counts an element without a key each time it is asked, and stores nothing for it" do
    root = body('<div><p>Coffee <a href="/roast">roasted <b>dark</b></a></p></div>')
    stats = described_class.new(root)
    bold = root.at_css("b")
    bold.remove_attribute(Nokodown::Dom::KEY)
    stored = stats.instance_variable_get(:@counts).dup

    [stats.chars(bold), stats.link_chars(bold), stats.text_chars(bold), stats.link_density(bold)].should == [4.0, 4.0, 0.0, 1.0]
    bold.add_child("er")
    stats.chars(bold).should == 6.0
    stats.instance_variable_get(:@counts).should == stored
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

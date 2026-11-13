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
end

# frozen_string_literal: true

RSpec.describe Nokodown::Listing do
  def root(html)
    node = Nokolexbor::HTML("<body><div class='content'>#{html}</div></body>").at_css("div.content")
    Nokodown::Dom.assign_keys(node)
    node
  end

  def items(html)
    described_class.items(root(html)).map { |item| item["class"] || item.name }
  end

  def post(index, heading: "<h2><a href='/posts/#{index}'>Post #{index}</a></h2>", extra: "")
    "<div class='post-item'>#{heading}#{extra}<p>#{'Our gardeners explain the method step by step, with photos. ' * 2}</p></div>"
  end

  it "finds the run of teasers that holds most of the text" do
    items("<div class='posts'>#{Array.new(3) { |index| post(index) }.join}</div><p>Page 1 of 4</p>").should == ["post-item"] * 3
  end

  it "counts every run toward the text, so a shop's products with only prices for text count beside its posts" do
    products = Array.new(4) { |index| "<li class='product'><h4><a href='/p/#{index}'>Bowl #{index}</a></h4><span>$8.99</span></li>" }

    items("<ul class='grid'>#{products.join}</ul><div class='posts'>#{Array.new(3) { |index| post(index) }.join}</div>").should include("product")
  end

  it "leaves out menus, whose items hold no text of their own" do
    menu = Array.new(4) { |index| "<li class='menu-item'><a href='/section/#{index}'>Section #{index}</a></li>" }

    items("<ul class='menu'>#{menu.join}</ul><div class='posts'>#{Array.new(3) { |index| post(index) }.join}</div>").should_not include("menu-item")
  end

  it "takes a featured post in a block of its own beside the run" do
    featured = "<div class='items-leading'><div class='leading-0'><h2><a href='/posts/9'>Featured</a></h2><p>A short summary.</p></div></div>"

    items("#{featured}<div class='items-row'>#{Array.new(3) { |index| post(index) }.join}</div>").should include("items-leading")
  end

  it "leaves out a run that holds little of the text" do
    essay = "<p>#{'The essay goes on for a long while about soil, water and the patience gardens ask for. ' * 20}</p>"

    items(essay + Array.new(3) { |index| post(index) }.join).should == []
  end

  it "leaves out sections whose headings link to themselves" do
    sections = Array.new(3) { |index| post(index, heading: "<h2><a href='#part-#{index}'>Part #{index}</a></h2>", extra: "<a href='/ref'>ref</a>") }

    items(sections.join).should == []
  end

  it "leaves out items with more headings than a title and a subtitle" do
    headings = "<h2><a href='/a'>Title</a></h2><h3>Subtitle</h3><h3>Another section</h3>"

    items(Array.new(3) { |index| post(index, heading: headings) }.join).should == []
  end

  it "leaves out reference entries that hold signatures or code" do
    entries = Array.new(3) { |index| post(index, extra: "<table><tr><td>int f(int n)</td></tr></table>") }

    items(entries.join).should == []
  end
end

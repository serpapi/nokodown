# frozen_string_literal: true

RSpec.describe Nokodown::ContainerCheck do
  def remove?(html)
    root = Nokolexbor::HTML("<body><div class='story'>#{html}</div></body>").at_css("div.story")
    Nokodown::Dom.assign_keys(root)
    described_class.new(root, 1000, Set.new).remove?
  end

  it "counts each embed once whichever rule reads them" do
    remove?("<p>Watch the reopening.</p><iframe src='https://example.com/a'></iframe><iframe src='https://example.com/b'></iframe>").should be(true)
    remove?("<p>#{'Crews replaced six bearings and resurfaced both ramps. ' * 2}</p><iframe src='https://example.com/a'></iframe>").should be(false)
  end

  it "counts list items and inputs against the paragraphs" do
    words = "<b>#{'Crews replaced six bearings and resurfaced both ramps. ' * 3}</b>"
    items = ->(count) { "<ul>#{'<li>x</li>' * count}</ul>" }
    remove?(words + items.call(101)).should be(true)
    remove?(words + items.call(100)).should be(false)
    remove?("<p>#{'Crews replaced six bearings. ' * 4}</p><input type='text'>").should be(true)
    remove?("<p>#{'Crews replaced six bearings. ' * 4}</p>").should be(false)
  end

  it "asks the root once for each tag of inputs, players, embeds, images and list items" do
    root = Nokolexbor::HTML("<body><div class='story'>#{"<div><p>Crews replaced six bearings and resurfaced both ramps.</p><a href='/x'>more</a></div>" * 3}</div></body>").at_css("div.story")
    Nokodown::Dom.assign_keys(root)
    asked = Hash.new(0)
    Nokolexbor::Node.any_instance.stub(:css).and_wrap_original { |original, selector| asked[selector] += 1; original.call(selector) }
    Nokolexbor::Node.any_instance.stub(:at_css).and_wrap_original { |original, selector| asked[selector] += 1; original.call(selector) }
    memo = { root: root }
    root.css("div").to_a.each { |div| described_class.new(div, 1000, Set.new, memo).remove?.should be(false) }
    %w[input img li video audio object embed iframe].each { |name| asked[name].should == 1 }
    asked["video, audio"].should == 0
    asked["object, embed, iframe"].should == 0
  end

  it "still counts inputs in a root that has them" do
    root = Nokolexbor::HTML("<body><div class='story'><div><p>Crews replaced six bearings.</p><input type='text'></div><p>#{'Crews resurfaced both ramps. ' * 9}</p></div></body>").at_css("div.story")
    Nokodown::Dom.assign_keys(root)
    described_class.new(root.first_element_child, 1000, Set.new, root: root).remove?.should be(true)
  end

  describe "a container without text containers" do
    it "is removed when nothing in it holds text" do
      remove?("<span></span><em> </em><div><b></b></div>").should be(true)
    end

    it "is kept when a child text container holds text" do
      remove?("<p>Crews replaced six bearings and resurfaced both ramps.</p>").should be(false)
    end

    it "is kept when its loose text holds text" do
      remove?("<div></div><section><b>Crews replaced six bearings and resurfaced both ramps.</b></section>").should be(false)
    end
  end
end

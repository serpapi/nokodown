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

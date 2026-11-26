# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nokodown::Scorer do
  def score(html)
    body = Nokolexbor::HTML("<body>#{html}</body>").at_css("body")
    Nokodown::Dom.assign_keys(body)
    described_class.new(body, Nokodown::Stats.new(body)).call
  end

  # Readability gives a paragraph one point, one per piece between commas,
  # and one per 100 characters up to three.
  it "counts every comma Readability counts, a trailing one too" do
    result = score("<article><p>Beans, roasted\u060C ground\uFE50 brewed\uFF0Cand served,</p></article>")

    result.top.name.should == "article"
    result.score.should == 1 + 6
  end

  it "scores each paragraph without listing its ancestors" do
    paragraphs = Array.new(40) { "<p>Coffee is brewed from roasted beans, ground fine.</p>" }.join
    calls = 0
    trace = TracePoint.new(:call) do |point|
      calls += 1 if point.method_id == :ancestors && point.defined_class == Nokolexbor::Node
    end

    trace.enable { score("<div><section><article>#{paragraphs}</article></section></div>") }

    calls.should < 10
  end

  it "weighs class lists from the cache an extraction keeps as without it, and drops the cache after" do
    names = ["comment", "article", "comment", "content", "sidebar body", "", "h-social-media-tips", "article"]
    nodes = names.map { |name| Nokolexbor::HTML("<div class=\"#{name}\" id=\"x\"></div>").at_css("div") }
    weights = -> { nodes.map { |node| [described_class.class_weight(node), described_class.cleaning_weight(node)] } }
    uncached = weights.call

    cached = Nokodown::Dom.caching_signatures { Array.new(2) { weights.call } }

    uncached.map(&:first).should == [-25, 25, -25, 25, 0, 0, -25, 25]
    cached.should == [uncached, uncached]
    Thread.current[Nokodown::Dom::WEIGHTS].should be_nil
  end
end

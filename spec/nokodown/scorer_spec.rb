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
end

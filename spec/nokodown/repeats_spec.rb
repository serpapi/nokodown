# frozen_string_literal: true

RSpec.describe Nokodown::Markdown::Repeats do
  let(:intro) { "<p>Fits a one litre pot and boils water in three minutes.</p>" }

  describe "copies of the title" do
    it "drops headings and paragraphs that repeat the H1" do
      html = "<p><b>Trail Stove 2</b></p><h1>Trail Stove 2</h1><h2><a href='/stove'>Trail Stove 2</a></h2>#{intro}<p>Trail stove 2</p>"
      convert(html).should == "# Trail Stove 2\n\nFits a one litre pot and boils water in three minutes."
    end

    it "drops a part of a page and site title near the top" do
      convert("<h1>Trail Stove 2 - Camp Shop</h1><p>Camp Shop</p><p>Trail Stove 2</p>#{intro}").should ==
        "# Trail Stove 2 - Camp Shop\n\nFits a one litre pot and boils water in three minutes."
    end

    it "keeps a paragraph that repeats the title as a link to another page" do
      html = "<h1>Stove review</h1>#{intro}<iframe src='https://www.youtube.com/embed/dQw4w9WgXcQ' title='Stove review'></iframe>"
      convert(html).should end_with("[Stove review](https://www.youtube.com/watch?v=dQw4w9WgXcQ)")
    end
  end

  describe "labels that repeat a heading" do
    it "drops a short label over a heading that contains it" do
      convert("<h1>Salkantay trek</h1>#{intro}<p>ITINERARY</p><hr><h2>Full itinerary for four days</h2><p>Day one.</p>").should ==
        "# Salkantay trek\n\nFits a one litre pot and boils water in three minutes.\n\n---\n\n## Full itinerary for four days\n\nDay one."
    end

    it "keeps a short answer that opens the section above the heading" do
      convert("<h3>Is it free?</h3><p>Yes</p><h3>Yes, but for how long?</h3><p>A year.</p>").should ==
        "### Is it free?\n\nYes\n\n### Yes, but for how long?\n\nA year."
    end

    it "drops a paragraph that repeats a heading just above" do
      html = "<article><h3>Pumas win the first leg</h3><p>4/2/2026</p></article><article><p>Pumas win the first leg</p><p>4/2/2026</p></article>"
      convert(html).should == "### Pumas win the first leg\n\n4/2/2026"
    end

    it "drops a list whose items are the headings of the page" do
      html = "<ul><li>Overview</li><li>Specifications</li></ul><h2>Overview</h2>#{intro}<h2>Specifications</h2><p>85 grams.</p>"
      convert(html).should == "## Overview\n\nFits a one litre pot and boils water in three minutes.\n\n## Specifications\n\n85 grams."
    end
  end

  it "drops a block that follows its own copy" do
    blocks = [Nokodown::Markdown::Block.new(:paragraph, "Provo Bench"), Nokodown::Markdown::Block.new(:paragraph, "Provo Bench")]
    described_class.call(blocks).map(&:text).should == ["Provo Bench"]
  end
end

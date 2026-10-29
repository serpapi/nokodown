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

    it "keeps a part of the title away from the top" do
      notes = ["Pitted.", "Store cool.", "Serve chilled.", "Keeps a month.", "From Puglia.", "Since 1950.", "Organic.", "Hand picked."]
      html = "<h1>Green olives - Camp Shop</h1>#{notes.map { |note| "<p>#{note}</p>" }.join}<p>Camp Shop</p>"
      convert(html).should end_with("Hand picked.\n\nCamp Shop")
    end

    it "keeps the first line of a poem that gives the poem its name" do
      convert("<h1>The aesthete</h1><p>The aesthete,</p><p>the aesthete</p><p>turns left at once</p>").should ==
        "# The aesthete\n\nThe aesthete,\n\nthe aesthete\n\nturns left at once"
    end

    it "drops a copy of the title over an embedded video, whose address does not run on from it" do
      html = "<h1>Pasta at home</h1>#{intro}<p>Pasta at home</p>" \
             '<iframe src="https://www.youtube.com/embed/dQw4w9WgXcQ"></iframe>'
      convert(html).should == "# Pasta at home\n\nFits a one litre pot and boils water in three minutes.\n\nhttps://www.youtube.com/watch?v=dQw4w9WgXcQ"
    end

    it "keeps a copy that is all a section holds" do
      convert("<h1>Central Asia - Travel Blog</h1><h3>Tag</h3><p>Central Asia</p>").should ==
        "# Central Asia - Travel Blog\n\n### Tag\n\nCentral Asia"
    end

    it "keeps a linked heading named like the title away from it" do
      notes = ["Pitted.", "Store cool.", "Serve chilled.", "Keeps a month.", "From Puglia.", "Since 1950.", "Organic.", "Hand picked."]
      html = "<h1>Green olives, 1 kg jar</h1>#{notes.map { |note| "<p>#{note}</p>" }.join}" \
             "<h3><a href='/olives-2'>Green olives, 1 kg jar</a></h3><p>In brine.</p>"
      convert(html).should end_with("### [Green olives, 1 kg jar](https://example.com/olives-2)\n\nIn brine.")
    end

    it "keeps a heading named like the title away from it over a section of its own" do
      notes = ["Pitted.", "Store cool.", "Serve chilled.", "Keeps a month.", "From Puglia.", "Since 1950.", "Organic.", "Hand picked."]
      html = "<h1>Green olives</h1>#{notes.map { |note| "<p>#{note}</p>" }.join}<h2>Shipping</h2><p>Two days.</p>" \
             "<h2>Green olives</h2><p>Weight: 1 kg.</p>"
      convert(html).should end_with("## Shipping\n\nTwo days.\n\n## Green olives\n\nWeight: 1 kg.")
    end

    it "keeps a heading that differs from the title by a vowel sign" do
      convert("<h1>किताबें</h1>#{intro}<h2>किताब</h2><p>एक किताब के बारे में।</p>").should include("## किताब")
    end

    it "keeps a paragraph that repeats the title as a link to another page" do
      html = "<h1>Stove review</h1>#{intro}<iframe src='https://www.youtube.com/embed/dQw4w9WgXcQ' title='Stove review'></iframe>"
      convert(html).should end_with("[Stove review](https://www.youtube.com/watch?v=dQw4w9WgXcQ)")
    end
  end

  describe "labels that repeat a heading" do
    it "drops a short label over a heading that contains it" do
      convert("<h1>Salkantay trek</h1>#{intro}<p>ITINERARY</p><hr><h2>Full itinerary for four days</h2><p>Day one.</p>").should ==
        "# Salkantay trek\n\nFits a one litre pot and boils water in three minutes.\n\n## Full itinerary for four days\n\nDay one."
    end

    it "keeps a short answer that opens the section above the heading" do
      convert("<h3>Is it free?</h3><p>Yes</p><h3>Yes, but for how long?</h3><p>A year.</p>").should ==
        "### Is it free?\n\nYes\n\n### Yes, but for how long?\n\nA year."
    end

    it "drops a paragraph of any length that repeats the heading below it" do
      title = "How to choose the best mascot for an online shop"
      convert("<h2>Similar</h2><p>#{title}</p><h4><a href='/mascot'>#{title}</a></h4><p>March 23, 2026</p>").should ==
        "## Similar\n\n#### [#{title}](https://example.com/mascot)\n\nMarch 23, 2026"
    end

    it "drops a paragraph that repeats a heading just above" do
      html = "<article><h3>Pumas win the first leg</h3><p>4/2/2026</p></article><article><p>Pumas win the first leg</p><p>4/2/2026</p></article>"
      convert(html).should == "### Pumas win the first leg\n\n4/2/2026"
    end

    it "keeps a link over a heading that repeats its name without it" do
      convert("<p><a href='/kettles/1'>Stovetop kettle</a></p><h3>Stovetop kettle</h3><p>Holds 1.5 litres.</p>").should ==
        "[Stovetop kettle](https://example.com/kettles/1)\n\n### Stovetop kettle\n\nHolds 1.5 litres."
    end

    it "keeps a list of images under a heading of symbols" do
      html = "<h2>🎁</h2><p>Gifts we picked.</p><ul><li><img src='/a.jpg' alt='Red scarf'></li><li><img src='/b.jpg' alt='Wool hat'></li></ul>" \
             "<h2>Prices</h2><p>From $10.</p>"
      convert(html).should include("- ![Red scarf](https://example.com/a.jpg)")
    end

    it "drops a list whose items are the headings of the page" do
      html = "<ul><li>Overview</li><li>Specifications</li></ul><h2>Overview</h2>#{intro}<h2>Specifications</h2><p>85 grams.</p>"
      convert(html).should == "## Overview\n\nFits a one litre pot and boils water in three minutes.\n\n## Specifications\n\n85 grams."
    end
  end

  it "drops a gallery's thumbnail strip whose alt texts are file names" do
    photos = %w[a b].map { |name| "<p><img src='/photos/#{name}.jpg' alt=''></p>" }.join
    thumbs = %w[a b].map { |name| "<img src='/photos/#{name}.jpg' alt='#{name}.jpg'>" }.join(" ")
    convert("#{photos}<p>Self portraits in oil.</p><p>#{thumbs}</p>").should ==
      "![](https://example.com/photos/a.jpg)\n\n![](https://example.com/photos/b.jpg)\n\nSelf portraits in oil."
  end

  it "drops a thumbnail strip whose alt texts say nothing the way Inline reads alt text" do
    photos = %w[a b].map { |name| "<p><img src='/photos/#{name}.jpg' alt=''></p>" }.join
    thumbs = %w[a b].map { |name| "<img src='/photos/#{name}.jpg' alt='DSC0825#{name.ord}'>" }.join(" ")
    convert("#{photos}<p>Self portraits in oil.</p><p>#{thumbs}</p>").should ==
      "![](https://example.com/photos/a.jpg)\n\n![](https://example.com/photos/b.jpg)\n\nSelf portraits in oil."
  end

  it "drops a block that follows its own copy" do
    blocks = [Nokodown::Markdown::Block.new(:paragraph, "Provo Bench"), Nokodown::Markdown::Block.new(:paragraph, "Provo Bench")]
    described_class.call(blocks).map(&:text).should == ["Provo Bench"]
  end
end

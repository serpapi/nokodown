# frozen_string_literal: true

RSpec.describe Nokodown::Markdown::Orphans do
  it "drops numbers without a label, such as comment counts and FAQ badges" do
    html = "<p><a href='/author/jo'>Jo Pine</a></p><p>0</p><p>Common questions about the stove.</p>" \
           "<div>1</div><h3>How fast does it boil?</h3><p>Three minutes.</p>"
    convert(html).should == "[Jo Pine](https://example.com/author/jo)\n\nCommon questions about the stove.\n\n" \
                            "### How fast does it boil?\n\nThree minutes."
  end

  it "keeps a number after a heading or a label, or before a label" do
    html = "<h3>Rooms</h3><p>3</p><p>Baths:</p><p>2</p><p>Our team is growing.</p><p>250</p><p>Employees</p>"
    convert(html).should == "### Rooms\n\n3\n\nBaths:\n\n2\n\nOur team is growing.\n\n250\n\nEmployees"
  end

  it "keeps a number that the next line runs on from" do
    convert("<p>The chain opened a new store.</p><p><b>17</b></p><p>stores in the city now carry its name.</p>").should ==
      "The chain opened a new store.\n\n**17**\n\nstores in the city now carry its name."
  end

  it "drops slide numbers and a player's empty time readout, but keeps a phone number" do
    convert("<p>1 2 3 4 5 6</p><p>0:00 / 3:45</p><p>Call us.</p><p>777 326 454</p>").should == "Call us.\n\n777 326 454"
  end

  it "drops labels left without their value, such as a form's fields and a list of tags at the end" do
    convert("<p>Write to us.</p><p>Your name:</p><p>E-mail:</p><p>Subject:</p><h2>Stoves</h2><p>Light.</p><p>Tags:</p>").should ==
      "Write to us.\n\n## Stoves\n\nLight."
  end

  it "keeps a label before its value, a heading or a list" do
    html = "<p>Price:</p><p>$40</p><p>Reviewed article:</p><h2>Weaving in ancient Greece</h2><p>Sizes:</p><ul><li>S</li><li>M</li></ul>"
    convert(html).should == "Price:\n\n$40\n\nReviewed article:\n\n## Weaving in ancient Greece\n\nSizes:\n\n- S\n- M"
  end

  it "keeps labels followed by text, as in a template a post sets out" do
    convert("<p>Copy this:</p><p><b>Your nickname:</b></p><p><b>Your district:</b></p><p>See you soon!</p>").should ==
      "Copy this:\n\n**Your nickname:**\n\n**Your district:**\n\nSee you soon!"
  end
end

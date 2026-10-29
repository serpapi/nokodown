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

  it "keeps numbers side by side, but not the options of a picker" do
    html = "<p>News from the scene.</p><p>149</p><p>25</p><p>House in Mijas.</p><p>5</p><p>393m²</p>" \
           "<p>Pick how many you need.</p><p>1</p><p>2</p><p>3</p><p>Pick a page.</p><p>2</p><p>3</p><p>4</p>"
    convert(html).should == "News from the scene.\n\n149\n\n25\n\nHouse in Mijas.\n\n5\n\n393m²\n\n" \
                            "Pick how many you need.\n\nPick a page."
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

  it "drops the heading of a section that held only labels left without their value" do
    convert("<p>Write to us.</p><h2>Contact us</h2><p>Your name:</p><p>E-mail:</p>").should == "Write to us."
  end

  it "keeps a lone midnight slot and a row of departures" do
    departures = (0...24).map { |i| format("%<hour>d:%<minute>02d", hour: i / 4, minute: (i % 4) * 15) }.join(" ")
    convert("<p>00:00</p><p>Night news.</p><p>#{departures} (no service on holidays)</p>").should ==
      "00:00\n\nNight news.\n\n#{departures} (no service on holidays)"
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

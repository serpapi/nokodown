# frozen_string_literal: true

RSpec.describe Nokodown::Markdown::Counters do
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

  it "drops slide numbers and a player's empty time readout, but keeps a phone number" do
    convert("<p>1 2 3 4 5 6</p><p>0:00 / 3:45</p><p>Call us.</p><p>777 326 454</p>").should == "Call us.\n\n777 326 454"
  end
end

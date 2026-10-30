# frozen_string_literal: true

RSpec.describe Nokodown::InPageLinks do
  def listed(html)
    body = Nokolexbor::HTML("<body>#{html}</body>").at_css("body")
    described_class.mark_listed(body)
    body.css("[#{described_class::LISTED}]").map { |node| node["id"] }
  end

  def section(id, heading)
    "<section id='#{id}'><a href='##{id}'><header><h2>#{heading}</h2></header></a><p>#{heading} of the boots.</p></section>"
  end

  let(:sections) { section("set", "Full set") + section("recipes", "Used in recipes") + section("pictures", "Pictures") }

  it "marks the sections that a table of contents lists" do
    toc = "<nav><ul><li><a href='#set'>Full set</a></li><li><a href='#recipes'>Recipes</a></li>" \
          "<li><a href='#pictures'>Pictures</a></li></ul></nav>"

    listed(toc + sections).should == %w[set recipes pictures]
  end

  it "does not take the permalinks of the headings for a table of contents" do
    listed("<ul><li>#{sections}</li></ul>").should be_empty
  end

  it "marks no part that a list of skip links leads to" do
    skips = "<ul><li><a href='#main'>Skip to content</a></li><li><a href='#menu'>Skip to menu</a></li>" \
            "<li><a href='#footer'>Skip to footer</a></li></ul>"
    page = "<nav id='menu'><a href='/'>Home</a></nav><main id='main'><h1>Boots</h1></main><footer id='footer'>Contact</footer>"

    listed(skips + page).should be_empty
  end

  it "marks only the innermost of the parts it lists" do
    toc = "<ol><li><a href='#main'>Boots</a></li><li><a href='#set'>Full set</a></li>" \
          "<li><a href='#recipes'>Recipes</a></li><li><a href='#pictures'>Pictures</a></li></ol>"

    listed("#{toc}<main id='main'><h1>Boots</h1>#{sections}</main>").should == %w[set recipes pictures]
  end
end

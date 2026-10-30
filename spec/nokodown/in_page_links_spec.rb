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

  def in_page_links(html)
    root = Nokolexbor::HTML("<body>#{html}</body>").at_css("body")
    Nokodown::Dom.assign_keys(root)
    described_class.new(root, described_class.anchors(root.document), nil)
  end

  # Unclosed tags nest each link one level below the one before.
  def nested_links(count)
    in_page_links((1..count).map { |number| "<div><a href='/items/#{number}'>Item #{number}</a> " }.join)
  end

  let(:sections) { section("set", "Full set") + section("recipes", "Used in recipes") + section("pictures", "Pictures") }
  let(:contents_list) do
    "<ul><li><a href='#set'>Full set</a></li><li><a href='#recipes'>Recipes</a></li>" \
      "<li><a href='#pictures'>Pictures</a></li></ul>"
  end

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

  it "finds a table of contents in the clones of a font left open, which share one key" do
    links = in_page_links("<p id='top'><font face='Arial'>Boots. <a href='#top'>Top</a>#{contents_list}#{sections}")

    links.contents.map(&:name).should == %w[ul]
  end

  it "reads the links of no container on a page without links into it" do
    links = nested_links(3000)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    links.contents.should be_empty

    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).should < 1
  end

  it "reads the text of no link that leads off the page" do
    links = nested_links(3000)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    links.back_links.should be_empty

    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).should < 1
  end
end

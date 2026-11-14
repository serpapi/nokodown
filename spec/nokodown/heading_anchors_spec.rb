# frozen_string_literal: true

RSpec.describe Nokodown::HeadingAnchors do
  def anchor?(html)
    body = Nokolexbor::HTML("<body>#{html}</body>").at_css("body")
    described_class.anchor?(body.at_css("[id]"))
  end

  it "recognizes ids made from a heading's text, with a one-letter prefix or a counter" do
    anchor?('<h2 id="h-what-s-next-for-social-shopping">What’s Next for Social Shopping?</h2>').should == true
    anchor?('<h3 id="travel-related-coverage-2">Travel-Related Coverage</h3>').should == true
    anchor?('<h3 id="Login_shell">Login shell</h3>').should == true
    anchor?('<h2 id="H-Social-Tips">Social Tips</h2>').should == true
    anchor?('<h2 id="que-es-el-marketing-social">Qué es el marketing social</h2>').should == true
    anchor?('<h2><span class="mw-headline" id="Related_to_Portage">Related to Portage</span></h2>').should == true
  end

  it "recognizes the id of the section a heading opens" do
    anchor?('<section id="cookies"><h3>Cookies<a href="#cookies">¶</a></h3><p>Read them from the request.</p></section>').should == true
    anchor?('<section id="s-sharing-models"><span id="sharing-models"></span><h4>Sharing models</h4><p>Import them.</p></section>').should == true
  end

  it "does not take other ids for anchors" do
    anchor?('<h3 id="social-links">Follow our journey</h3>').should == false
    anchor?('<div id="social-feed"><p>Latest posts.</p><h2>Social feed</h2></div>').should == false
    anchor?('<a id="social-sharing">Social sharing</a>').should == false
  end

  it "does not take the id of a junk label for an anchor, since it names the widget under it" do
    anchor?('<h2 id="related-posts">Related posts</h2>').should == false
    anchor?('<h3 id="share-this-article">Share this article</h3>').should == false
    anchor?('<h2 id="feedback">Feedback</h2>').should == false
    anchor?('<h2 id="table-of-contents">Table of contents</h2>').should == false
    anchor?('<h2 id="customer-reviews">Customer Reviews</h2>').should == false
    anchor?('<section id="ratings-and-reviews"><h2>Ratings and Reviews</h2><p>Sturdy and light.</p></section>').should == false
  end

  it "reads a junk label without the permalink that anchor markup adds to it" do
    anchor?('<section id="comments"><h2>Comments<a href="#comments">¶</a></h2><p>Jane wrote: thanks.</p></section>').should == false
    anchor?('<h2 id="related-articles">Related articles <a class="anchor" href="#related-articles">#</a></h2>').should == false
    anchor?('<h3 id="share-this-article"><a href="#share-this-article">#</a> Share this article</h3>').should == false
    anchor?(%(<h2 class="anchor" id="related-posts">Related posts<a class="hash-link" href="#related-posts">\u200B</a></h2>)).should == false
  end

  # Enough other elements that only those around the headings are read.
  let(:filler) { "<p id='filler'>Filler</p>" * 100 }

  it "marks the anchors around every heading, and nothing else" do
    html = '<body id="intro-2"><h2 id="intro">Intro</h2><div><section id="s-setup"><span id="setup"></span>' \
           '<h3><span class="mw-headline" id="Setup">Setup</span></h3><p id="setup-2">Setup</p></section>' \
           '<div id="usage"><div><h4 id="x">Usage</h4></div></div></div>' + filler + '</body>'
    body = Nokolexbor::HTML(html).at_css("body")
    described_class.should_receive(:mark_around).at_least(:once).and_call_original
    described_class.mark(body)
    body.css("[#{Nokodown::Dom::ANCHOR}]").map { |node| node["id"] }.sort.should == %w[Setup intro s-setup]
    body.key?(Nokodown::Dom::ANCHOR).should == false
  end

  it "reads each element once, however many headings it holds" do
    html = '<body><h1>Title<h1><div id="content"><h2 id="a">A</h2><p>a</p><h2 id="b">B</h2><p>b</p>' \
           '<h2>C</h2></div><section id="c"><h3>C</h3><h4 id="d"><span id="e">D</span><h5>E</h5></h4></section>' + filler + '</body>'
    body = Nokolexbor::HTML(html).at_css("body")
    ids = []
    described_class.stub(:anchor?).and_wrap_original do |original, node|
      ids << node["id"]
      original.call(node)
    end
    described_class.should_receive(:mark_around).at_least(:once).and_call_original
    described_class.mark(body)
    ids.sort.should == %w[a b c content d e]
  end

  it "reads a parent once without stepping back over its children for every heading" do
    html = "<body><article id='post'><h1>A short title</h1>#{('<h2>Section</h2>' + '<span></span>' * 8) * 20}</article>" + filler + "</body>"
    body = Nokolexbor::HTML(html).at_css("body")
    Nokolexbor::Node.any_instance.should_not_receive(:previous_element)
    described_class.should_receive(:anchor?).once.and_call_original
    described_class.mark(body)
  end

  it "reads each parent once when many share an id" do
    html = "<body>#{"<section id='intro'><h2>Intro</h2><p>Text</p><h2>More</h2></section>" * 12}" + filler * 3 + "</body>"
    body = Nokolexbor::HTML(html).at_css("body")
    described_class.should_receive(:mark_around).at_least(:once).and_call_original
    described_class.should_receive(:anchor?).exactly(12).times.and_call_original
    described_class.mark(body)
    body.css("section[#{Nokodown::Dom::ANCHOR}]").size.should == 12
  end

  it "reads every element with an id where headings are most of the page" do
    html = "<body><article id='post'><h1>A short title</h1>#{'<h2>Section</h2>' * 100}<h2 id='notes'>Notes</h2>" \
           "<p id='filler'>Filler</p></article></body>"
    body = Nokolexbor::HTML(html).at_css("body")
    described_class.should_not_receive(:reads_parent?)
    described_class.mark(body)
    body.css("[#{Nokodown::Dom::ANCHOR}]").map { |node| node["id"] }.should == %w[notes]
  end
end

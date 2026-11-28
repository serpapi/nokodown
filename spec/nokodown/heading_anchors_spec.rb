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

  it "steps back over a parent's children from its first heading only" do
    html = "<body><article id='post'><h1>A short title</h1>#{('<h2>Section</h2>' + '<span></span>' * 8) * 20}</article>" + filler + "</body>"
    body = Nokolexbor::HTML(html).at_css("body")
    steps = 0
    Nokolexbor::Node.any_instance.stub(:previous_element).and_wrap_original { |original| steps += 1; original.call }
    described_class.should_receive(:anchor?).once.and_call_original
    described_class.mark(body)
    steps.should == 1
  end

  it "reads each parent once when many share an id" do
    html = "<body>#{"<section id='intro'><h2>Intro</h2><div><h3>Text</h3></div><h2>More</h2></section>" * 12}" + filler * 3 + "</body>"
    body = Nokolexbor::HTML(html).at_css("body")
    described_class.should_receive(:mark_around).at_least(:once).and_call_original
    described_class.should_receive(:anchor?).exactly(12).times.and_call_original
    described_class.mark(body)
    body.css("section[#{Nokodown::Dom::ANCHOR}]").size.should == 12
  end

  it "reads a parent once, however many parents before it share its id" do
    html = "<body>#{"<section id='post'><h2>Intro</h2></section>" * 8}<article id='post'><h1>A short title</h1>" \
           "#{('<h2>Section</h2>' + '<span></span>' * 8) * 20}</article>" + filler + "</body>"
    body = Nokolexbor::HTML(html).at_css("body")
    steps = 0
    Nokolexbor::Node.any_instance.stub(:previous_element).and_wrap_original { |original| steps += 1; original.call }
    described_class.should_receive(:mark_around).at_least(:once).and_call_original
    described_class.should_receive(:anchor?).exactly(9).times.and_call_original
    described_class.mark(body)
    steps.should == 9
  end

  it "reads a parent's id once, however many headings it holds" do
    html = "<body><article id='#{'post' * 100}'><h1>A short title</h1>#{'<h2>Section</h2><p>Text</p>' * 20}</article>" + filler * 3 + "</body>"
    body = Nokolexbor::HTML(html).at_css("body")
    ids = 0
    Nokolexbor::Node.any_instance.stub(:[]).and_wrap_original do |original, name|
      ids += 1 if name == "id"
      original.call(name)
    end
    described_class.should_receive(:mark_around).at_least(:once).and_call_original
    described_class.mark(body)
    ids.should == 1
  end

  it "tells at once that a heading does not open its parent's section" do
    unit = "<h2>Section</h2>#{'<span></span>' * 8}<div><h3>Part</h3></div>#{'<span></span>' * 8}"
    html = "<body><article id='post'><h1>A short title</h1>#{unit * 20}</article>" + filler + "</body>"
    body = Nokolexbor::HTML(html).at_css("body")
    steps = 0
    Nokolexbor::Node.any_instance.stub(:previous_element).and_wrap_original { |original| steps += 1; original.call }
    described_class.should_receive(:mark_around).at_least(:once).and_call_original
    described_class.should_receive(:anchor?).once.and_call_original
    described_class.mark(body)
    steps.should == 40
  end

  it "looks up a parent's id once, however often its headings take turns with another parent's" do
    unit = "<h2>Section</h2><div><h3>Part</h3></div>"
    html = "<body><article class='post'><h1>A short title</h1>#{unit * 20}</article>" + filler * 3 + "</body>"
    body = Nokolexbor::HTML(html).at_css("body")
    ids = 0
    Nokolexbor::Node.any_instance.stub(:key?).and_wrap_original do |original, name|
      ids += 1 if name == "id" && original.receiver.name == "article"
      original.call(name)
    end
    described_class.should_receive(:mark_around).at_least(:once).and_call_original
    described_class.mark(body)
    ids.should == 1
  end

  it "reads no text of a section without an id" do
    html = "<body><h1>A short title</h1><article>#{"<section><span>#{' ' * 1000}</span><h2>Setup</h2><br></section>" * 20}</article>" +
           filler * 4 + "</body>"
    body = Nokolexbor::HTML(html).at_css("body")
    described_class.should_receive(:mark_around).at_least(:once).and_call_original
    described_class.should_not_receive(:empty?)
    described_class.mark(body)
  end

  it "reads a section that opens with empty elements before its heading" do
    html = "<body><section id='setup'>#{'<span></span>' * 5}<a> </a><h2>Setup</h2><p>Text</p></section>" \
           "<section id='usage'><span></span><p>Intro</p><h2>Usage</h2></section>" + filler * 2 + "</body>"
    body = Nokolexbor::HTML(html).at_css("body")
    described_class.should_receive(:mark_around).at_least(:once).and_call_original
    described_class.mark(body)
    body.css("[#{Nokodown::Dom::ANCHOR}]").map { |node| node["id"] }.should == %w[setup]
  end

  it "reads each element with an id once where copies of one element sit around headings" do
    html = "<body><article><h2><b id='setup'>Setup</h2><p>Text</p>#{'<h2>Setup</h2><p>Text</p>' * 19}</article>" +
           filler * 2 + "</body>"
    body = Nokolexbor::HTML(html).at_css("body")
    described_class.should_receive(:mark_around_headings).and_call_original
    described_class.should_receive(:anchor?).exactly(body.css("[id]").size).times.and_call_original
    described_class.mark(body)
    body.css("[#{Nokodown::Dom::ANCHOR}]").should == body.css("b")
  end

  it "reads every element with an id where copies around headings were asked for their id out of order" do
    html = "<body><article><h2><b id='setup'>Setup</h2><p>Text</p>#{'<h2>Setup</h2><p>Text</p>' * 19}</article>" +
           filler * 2 + "</body>"
    body = Nokolexbor::HTML(html).at_css("body")
    body.css("b").reverse_each { |node| node.attribute("id") }
    described_class.should_receive(:mark_around_headings).and_wrap_original { |original, *args| original.call(*args).tap { |sparse| sparse.should == false } }
    described_class.mark(body)
    body.css("[#{Nokodown::Dom::ANCHOR}]").should == body.css("b")
  end

  it "reads only the elements around headings where elements apart share an id" do
    html = "<body><article>#{"<section><h2><b id='setup'>Setup</b></h2><p>Text</p></section>" * 20}</article>" +
           filler * 2 + "</body>"
    body = Nokolexbor::HTML(html).at_css("body")
    described_class.should_receive(:anchor?).exactly(20).times.and_call_original
    described_class.mark(body)
    body.css("[#{Nokodown::Dom::ANCHOR}]").map(&:name).should == %w[b] * 20
  end

  it "reads no id that no label could match, where elements the parser repeats sit around headings" do
    html = "<body><article>#{"<section><h2><b id='feedback'>Feedback</b></h2><p>Text</p></section>" * 20}</article>" +
           filler * 2 + "</body>"
    body = Nokolexbor::HTML(html).at_css("body")
    ids = 0
    Nokolexbor::Node.any_instance.stub(:[]).and_wrap_original { |original, name| ids += 1 if name == "id"; original.call(name) }
    described_class.should_receive(:mark_around_headings).and_call_original
    described_class.mark(body)
    ids.should == 0
    body.css("[#{Nokodown::Dom::ANCHOR}]").size.should == 0
  end

  it "reads every element with an id where headings are most of the page" do
    html = "<body><article id='post'><h1>A short title</h1>#{'<h2>Section</h2>' * 100}<h2 id='notes'>Notes</h2>" \
           "<p id='filler'>Filler</p></article></body>"
    body = Nokolexbor::HTML(html).at_css("body")
    described_class.should_not_receive(:mark_around_headings)
    described_class.mark(body)
    body.css("[#{Nokodown::Dom::ANCHOR}]").map { |node| node["id"] }.should == %w[notes]
  end
  it "reads every element with an id once telling which sections headings open takes long" do
    unit = "<h2>Section</h2>#{'<span></span>' * 8}<div><h3>Part</h3></div>#{'<span></span>' * 8}"
    html = "<body><article id='a-short-title'>#{'<span></span>' * 16}<h1>A short title</h1><p>Text</p>#{unit * 20}</article>" +
           filler + "</body>"
    body = Nokolexbor::HTML(html).at_css("body")
    steps = 0
    Nokolexbor::Node.any_instance.stub(:previous_element).and_wrap_original { |original| steps += 1; original.call }
    described_class.should_receive(:anchor?).exactly(101).times.and_call_original
    described_class.mark(body)
    steps.should < 80
    body.css("[#{Nokodown::Dom::ANCHOR}]").map { |node| node["id"] }.should == %w[a-short-title]
  end

  it "takes steps back from the budget telling which sections headings open" do
    unit = "<section><span> </span>#{'<br>' * 6}<h2>Setup</h2></section>"
    html = "<body><h1>Title</h1><p>Text</p><article>#{unit * 200}</article></body>"
    body = Nokolexbor::HTML(html).at_css("body")
    steps = 0
    Nokolexbor::Node.any_instance.stub(:previous_element).and_wrap_original { |original| steps += 1; original.call }
    described_class.mark(body)
    steps.should < 600
  end

  it "steps over the text a section opens with once telling which sections headings open" do
    unit = "<h2>Section</h2><div><h3>Part</h3></div>#{'<br>' * 14}"
    html = "<body><article id='post'>#{'a<script></script>' * 40_000}#{unit * 4000}</article></body>"
    body = Nokolexbor::HTML(html).at_css("body")
    body.css("script").each(&:remove)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    described_class.mark(body)
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).should < 0.5
  end
end

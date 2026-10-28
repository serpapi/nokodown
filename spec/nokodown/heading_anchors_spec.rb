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
end

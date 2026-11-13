# frozen_string_literal: true

RSpec.describe Nokodown::Preprocessor do
  it "removes the same junk with its XPath union as with the CSS list, at any depth" do
    junk = described_class::JUNK.split(",").map { |tag| "<#{tag}>x</#{tag}>" }.join
    html = "<body><div>#{junk}<p>#{junk.upcase}</p><table><tr><td>#{junk}</td></tr></table>" \
           "<math><mi>x</mi><script>m</script></math><svg><g><link/><style>s</style></g></svg>" \
           "<object><param name=a><embed></object><select><optgroup><option>o</option></optgroup></select>" \
           "<map><area></map><template><script>t</script></template><span>kept</span></div></body>"
    by_css, by_xpath = 2.times.map { Nokolexbor::HTML(html).at_css("body") }
    by_css.css(described_class::JUNK).each(&:remove)
    by_xpath.xpath(described_class::JUNK_XPATH).each(&:remove)
    by_xpath.css(described_class::JUNK).size.should == 0
    by_xpath.to_html.should == by_css.to_html
    by_xpath.to_html.should include("kept")
  end

  it "finds hidden candidates in one pass, as the selector list finds them and in document order" do
    described_class::HIDDEN_CANDIDATES.should start_with(":is(")
    html = "<body><div class='sr-only'><p hidden>a</p><span style='display:none'>b</span></div>" \
           "<section aria-hidden='true'><b class='Hidden'>c</b><i class='x hide'>d</i></section>" \
           "<ul><li class='d-none'>e</li><li>f</li></ul><table><tr><td style=''>g</td></tr></table></body>"
    body = Nokolexbor::HTML(html).at_css("body")
    found = body.css(described_class::HIDDEN_CANDIDATES).map(&:to_html)
    found.should == body.css(described_class::HIDDEN_SELECTORS.join(", ")).map(&:to_html)
    found.size.should == 7
  end

  it "restores link targets on the links XPath finds, whatever their case or nesting" do
    html = "<body><a data-href='/x'>x</a><A DATA-HREF='/u'>u</A><p><b><a href='/k' data-href='/no'>k</a></b></p>" \
           "<table><tr><td><a href='' data-url='/t'>t</a></td></tr></table></body>"
    body = Nokolexbor::HTML(html).at_css("body")
    body.stub(:css).and_call_original
    body.should_not_receive(:css).with("a")
    described_class.new(body, full: true).call
    body.xpath(".//a").map { |link| link["href"] }.should == ["/x", "/u", "/k", "/t"]
  end
end

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
end

# frozen_string_literal: true

RSpec.describe Nokodown::Dom do
  def element(attributes)
    Nokolexbor::HTML("<div #{attributes}></div>").at_css("div")
  end

  describe ".signature" do
    it "lowercases class and id and splits camelCase" do
      described_class.signature(element('class="adContainer siteNav2Bar" id="mainHeader"')).should ==
        "ad-container site-nav2-bar main-header"
    end

    it "drops generated ids and CSS module hashes" do
      node = element('class="w-node-b5343ad4-1c2e-ad12-9f0b-3c4d5e6f7a8b mdx-table_root__adKqa"')
      described_class.signature(node).should == "w-node-  mdx-table_root "
    end

    it "is empty without class and id" do
      described_class.signature(element('title="x"')).should == ""
    end

    it "gives the same signature from the cache an extraction keeps" do
      nodes = %w[adContainer adContainer cookieBanner].map { |name| element("class=\"#{name}\" id=\"x#{name}\"") }
      uncached = nodes.map { |node| described_class.signature(node) }

      cached = described_class.caching_signatures do
        Array.new(2) { nodes.map { |node| described_class.signature(node) } }
      end

      cached.should == [uncached, uncached]
      Thread.current[described_class::SIGNATURES].should be_nil
    end
  end
end

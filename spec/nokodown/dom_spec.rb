# frozen_string_literal: true

RSpec.describe Nokodown::Dom do
  def element(attributes)
    Nokolexbor::HTML("<div #{attributes}></div>").at_css("div")
  end

  describe ".ancestors_named" do
    it "lists the ancestors with the given names, nearest first" do
      doc = Nokolexbor::HTML("<table><tr><td><div><p><b>Cell</b></p></div></td></tr></table>")

      described_class.ancestors_named(doc.at_css("b"), "td", "p", "table").map(&:name).should == %w[p td table]
      described_class.ancestors_named(doc.at_css("b"), "figure").should == []
    end

    it "climbs out of a copy or a fragment without failing" do
      doc = Nokolexbor::HTML("<figure><p><b>Cell</b></p></figure>")
      copy = doc.at_css("p").dup

      described_class.ancestors_named(copy.at_css("b"), "p", "figure").map(&:name).should == %w[p]
      described_class.ancestors_named(doc.fragment("<i><b>x</b></i>").at_css("b"), "i").map(&:name).should == %w[i]
    end
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

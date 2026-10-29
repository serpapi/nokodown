# frozen_string_literal: true

RSpec.describe Nokodown::Pruner do
  def content(html)
    root = Nokolexbor::HTML("<body><div class='story'>#{html}</div></body>").at_css("div.story")
    Nokodown::Dom.assign_keys(root)
    root
  end

  let(:story) do
    "<p>The harbor bridge reopened to traffic on Tuesday, three weeks after inspectors found cracked bearings.</p>" \
      "<p>Crews replaced six bearings and resurfaced both ramps, finishing four days early in the dry weather.</p>"
  end
  let(:teasers) do
    headlines = ["School board approves a new budget for next year", "Fishing season opens two weeks earlier than planned"]
    headlines.map do |headline|
      "<div class='card'><img src='/img/story.jpg' alt=''><h3><a href='/news/story'>#{headline}</a></h3></div>"
    end.join
  end
  let(:cards) do
    ["Cirrus Trail 3", "Scree Runner"].map do |name|
      "<div class='card'><img src='/img/shoe.jpg' alt=''><h3><a href='/products/shoe'>#{name}</a></h3>" \
        "<span>$129.00</span> <span>In stock, ships tomorrow</span></div>"
    end.join
  end

  describe "#conditional_share and #removed_link_share" do
    it "measure how much text conditional cleaning kept and how much of what it removed was links" do
      root = content(story + teasers)
      seen = Nokodown::Dom.text(root).length
      pruner = described_class.new([root], :article).call

      Nokodown::Dom.text(root).should_not include("School board")
      pruner.conditional_share.should == Nokodown::Dom.text(root).length.fdiv(seen)
      pruner.removed_link_share.should == 1.0
    end

    it "report that everything was kept when conditional cleaning did not run" do
      pruner = described_class.new([content(story + teasers)], :page).call

      pruner.conditional_share.should == 1.0
      pruner.removed_link_share.should == 0.0
    end
  end

  describe "page pruning" do
    it "keeps a teaser's short linked title with its date and author links, not a menu of linked headings" do
      teaser = "<header><h2><a href='/archives/42822'>ショップが新しくなりました</a></h2>" \
               "<a href='/archives/42822'>2021年03月09日</a> <a href='/author/micasa'>micasa</a></header>"
      menu = "<div><h3><a href='/men'>Men</a></h3><h3><a href='/women'>Women</a></h3><h3><a href='/sale'>Sale</a></h3></div>"
      root = content(teaser + story + menu)
      described_class.new([root], :page).call
      text = Nokodown::Dom.text(root)

      text.should include("ショップが新しくなりました2021年03月09日 micasa")
      text.should_not include("Women")
    end

    it "drops a menu or a widget under a single linked heading" do
      menu = "<div><h4><a href='/shop'>Shop</a></h4>" + %w[Men Women Kids Sale].map { |name| "<a href='/#{name}'>#{name}</a> " }.join + "</div>"
      icons = "<div><h3><a href='/login'>Login</a></h3>" + %w[x fb ig].map { |name| "<a href='https://#{name}.example'><img src='/#{name}.svg'></a>" }.join + "</div>"
      root = content(story + menu + icons)
      described_class.new([root], :page).call
      text = Nokodown::Dom.text(root)

      text.should_not include("Women")
      text.should_not include("Login")
    end

    it "drops counters a script never filled in" do
      root = content("#{story}<div class='like-icon'><a href=''>{{options.likeCount}}</a> <span>{{ options.likeCount }}</span></div>")
      described_class.new([root], :page).call

      Nokodown::Dom.text(root).should_not include("likeCount")
    end

    it "keeps template syntax shown as code" do
      block = "<div class='language-liquid highlighter-rouge'><div class='highlight'><pre><code>{{ page.title }}</code></pre></div></div>"
      root = content("#{story}#{block}<p><code>{{ site.url }}</code></p><ul><li><code>{{ content }}</code></li></ul>")
      described_class.new([root], :page).call

      %w[page.title site.url content].each { |name| Nokodown::Dom.text(root).should include("{{ #{name} }}") }
    end
  end

  describe "article pruning with conditional cleaning off" do
    let(:html) do
      "<p class='byline'>By Jo Pine</p>#{story}#{cards}" \
        "<h2>Related reading</h2><ul><li><a href='/guides/fit'>How to choose trail running shoes that fit</a></li>" \
        "<li><a href='/guides/plates'>Do you need a rock plate in your trail shoes?</a></li></ul>" \
        "<div><a href='/men'>Men</a> <a href='/women'>Women</a> <a href='/sale'>Sale</a></div>"
    end

    it "keeps the linky cards that conditional cleaning removes" do
      cleaned = content(html)
      described_class.new([cleaned], :article).call
      Nokodown::Dom.text(cleaned).should_not include("Cirrus Trail 3")

      root = content(html)
      described_class.new([root], :article, conditional: false).call
      Nokodown::Dom.text(root).should include("Cirrus Trail 3")
      Nokodown::Dom.text(root).should include("$129.00 In stock, ships tomorrow")
    end

    it "still drops the byline, the box of related links and the navigation" do
      root = content(html)
      described_class.new([root], :article, conditional: false).call
      text = Nokodown::Dom.text(root)

      ["Jo Pine", "Related reading", "How to choose", "Women"].each { |noise| text.should_not include(noise) }
    end
  end
end

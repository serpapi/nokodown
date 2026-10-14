# frozen_string_literal: true

RSpec.describe "Main content of different kinds of pages" do
  def extract(name)
    Nokodown.extract(fixture("#{name}.html"), url: "https://example.com/page")
  end

  describe "a news article" do
    let(:markdown) { extract("article").markdown }

    it "keeps the article body with its image, list, quote and table" do
      markdown.should include("![Aerial view of a tidal lagoon wall](https://example.com/images/lagoon.jpg)")
      markdown.should include("## Two-way turbines")
      markdown.should include("- Ebb generation produces about two thirds of annual output.")
      markdown.should include("> The tide is the most predictable renewable resource we have.")
      markdown.should include("| Sihwa Lake | 254 | 2011 |")
    end

    it "drops the page furniture around it" do
      ["cookies", "Skip to content", "[News]", "Home", "Share on", "Advertisement", "newsletter",
       "tidal, storage", "Related articles", "3 comments", "mudflats", "Popular", "All rights reserved"].each do |noise|
        markdown.should_not include(noise)
      end
    end

    it "moves the byline into metadata" do
      markdown.should_not include("Mara Lindqvist")
    end

    it "drops a comment section longer than the article" do
      comments = Array.new(15) do |index|
        %(<div class="comment"><p>Reader #{index} wonders how the lagoon walls will change the way the estuary silts up over the coming decades.</p></div>)
      end
      html = fixture("article.html").sub("<h2>3 comments</h2>", "<h2>18 comments</h2>#{comments.join}")

      Nokodown.extract(html, url: "https://example.com/page").markdown.should_not include("Reader 7 wonders")
    end
  end

  describe "a product page" do
    let(:markdown) { extract("product").markdown }

    it "keeps the title, price, description and specifications" do
      markdown.should include("# Trailhead 2 Hiking Boot")
      markdown.should include("$149.00")
      markdown.should include("A waterproof leather boot")
      markdown.should include("- Weight: 540 g per boot")
      markdown.should include("**Materials and care**")
      markdown.should include("- **Drop**: 12 mm")
    end

    it "drops navigation, cart controls, other products and popups" do
      ["Men", "Cart", "Add to cart", "Size", "Breadcrumb", "Ridge Runner", "Get 10% off", "Returns", "Free shipping"].each do |noise|
        markdown.should_not include(noise)
      end
    end
  end

  describe "a search results page" do
    let(:markdown) { extract("listing").markdown }

    it "keeps every result with its link and snippet" do
      markdown.should include("### [Perovskite cells pass a thousand-hour stability test](https://example.com/notes/perovskite-cells)")
      markdown.should include("Raised arrays shade lettuce and berries")
      markdown.should include("[88 comments](https://example.com/notes/balcony-solar#comments)")
    end

    it "drops the top bar, pagination and footer links" do
      ["login", "past", "Next", "Guidelines"].each { |noise| markdown.should_not include(noise) }
    end
  end

  describe "a documentation page" do
    let(:markdown) { extract("docs").markdown }

    it "keeps prose, code with its language and the options table" do
      markdown.should start_with("# Retries\n\n")
      markdown.should include("```ruby\nclient = Courier.new(retries: 3)\nclient.get(\"/status\")\n```")
      markdown.should include("*base* × 2<sup>attempt</sup>, capped at **30 seconds**")
      markdown.should include("| `retries` | 2 | Attempts after the first one |")
    end

    it "keeps comments in highlighted code" do
      markdown.should include("```ruby\n# Never wait more than 10 seconds\nclient = Courier.new(max_delay: 10)\n```")
    end

    it "drops the sidebar, table of contents, pager and feedback widget" do
      ["Installation", "Timeouts", "On this page", "Making requests", "Was this page helpful", "[#]"].each do |noise|
        markdown.should_not include(noise)
      end
    end
  end

  describe "a pricing page" do
    let(:markdown) { extract("pricing").markdown }

    it "keeps every plan with its price and features" do
      markdown.should include("Starter\n\n$0/ month\n\n- 3 users")
      markdown.should include("Business\n\n$49/ month\n\n- Unlimited users")
    end

    it "keeps collapsed FAQ answers" do
      markdown.should include("### Can I cancel at any time?\n\nYes. Plans are billed monthly")
    end

    it "drops the header, newsletter prompt and footer" do
      ["Features", "Log in", "Subscribe", "Ledgerly Inc"].each { |noise| markdown.should_not include(noise) }
    end
  end

  describe "a forum thread" do
    let(:markdown) { extract("forum").markdown }

    it "keeps every post, not just the highest scoring one" do
      markdown.should include("Is it ruined, or just hungry?")
      markdown.should include("Feed it twice at room temperature")
      markdown.should include("rebuild it with fresh rye flour")
    end

    it "drops the forum navigation and footer" do
      ["Latest", "Terms", "Rules"].each { |noise| markdown.should_not include(noise) }
    end
  end

  describe "a forum thread whose posts are named like comments" do
    it "keeps replies in a replies section" do
      markdown = extract("forum_replies").markdown

      markdown.should include("Is it realistic to plan the whole trip ourselves")
      markdown.should include("a two week rail pass covers Tokyo")
      markdown.should include("Kyoto alone deserves five days")
      markdown.should include("look at the Nakasendo trail")
      ["Guides", "Privacy"].each { |noise| markdown.should_not include(noise) }
    end

    it "keeps Vanilla comments under the opening post, though Readability weighs them down" do
      markdown = extract("forum_vanilla").markdown

      markdown.should include("we need to decide where this community goes next")
      markdown.should include("plan a weekend for redirects")
      markdown.should include("ask for a quote before the vote")
    end
  end

  describe "a Q&A page" do
    let(:markdown) { extract("qa").markdown }

    it "keeps the question and every answer" do
      markdown.should include("what is the difference between redundancy and a backup?")
      markdown.should include("RAID guards against one kind of failure")
      markdown.should include("redundancy gives you two copies of garbage")
      markdown.should include("snapshots on the array do not count as a backup")
    end

    it "drops the comments under the question and answers" do
      ["vendor's own guide", "controller firmware bugs", "sending this to my manager", "replicated to another site"].each do |comment|
        markdown.should_not include(comment)
      end
    end
  end
end

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

  describe "a category page with an intro above a card grid" do
    let(:markdown) { extract("collection").markdown }

    it "keeps the intro and every card with its link and price" do
      markdown.should include("Trail running shoes grip loose gravel")
      markdown.should include("### [Cirrus Trail 3](https://example.com/products/cirrus-trail-3)")
      markdown.should include("$189.00 Only 2 left in your size")
      markdown.should include("### [Sgurr Light](https://example.com/products/sgurr-light)")
    end

    it "drops the header and footer links" do
      ["Men", "Sale", "Returns", "Privacy"].each { |noise| markdown.should_not include(noise) }
    end

    it "still drops the byline and the box of related links, as article cleaning does" do
      ["Jo Pine", "Related reading", "How to choose"].each { |noise| markdown.should_not include(noise) }
    end
  end

  describe "a short news story above a grid of headline teasers" do
    let(:markdown) { extract("news_brief").markdown }

    it "keeps the story" do
      markdown.should include("Crews replaced six bearings")
      markdown.should include("the temporary ferry service ends on Friday.")
    end

    it "drops the teasers for other stories" do
      ["School board", "Fishing season", "Ferry company"].each { |noise| markdown.should_not include(noise) }
    end
  end

  describe "a recipe index made only of small linky cards" do
    let(:markdown) { extract("recipes").markdown }

    it "keeps every recipe with its link, blurb and cooking time" do
      markdown.should include("### [Charred leek and white bean soup](https://example.com/recipes/leek-and-bean-soup)")
      markdown.should include("Pearl barley, root vegetables and shredded chicken in a clear broth.")
      markdown.should include("45 min · Serves 4")
    end
  end

  describe "a blog post with a long comment thread" do
    let(:markdown) { extract("blog_post").markdown }

    it "keeps the post" do
      markdown.should include("The culprit turned out to be the flour.")
    end

    it "drops the comments and the box of links to older posts" do
      ["8 comments", "Same thing happened to me", "Further reading", "Protein content"].each do |noise|
        markdown.should_not include(noise)
      end
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
end

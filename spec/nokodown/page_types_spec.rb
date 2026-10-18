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

    it "drops customer reviews and questions but keeps the rating next to the price" do
      markdown.should include("$149.00\n\n212 reviews")
      ["Customer reviews", "Average 4.6", "Grippy on wet granite", "hut trip", "verified buyer", "Questions", "resole"].each do |noise|
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

    it "drops the top bar, result buttons, pagination and footer links" do
      ["login", "past", "Save", "Hide", "Next", "Guidelines"].each { |noise| markdown.should_not include(noise) }
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

    it "keeps comments in highlighted code" do
      markdown.should include("```ruby\n# Never wait more than 10 seconds\nclient = Courier.new(max_delay: 10)\n```")
    end

    it "keeps headings that carry a scroll-margin utility class" do
      markdown.should include("## Backoff\n\n")
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

  describe "a forum thread in a list of posts" do
    def thread(first_post, second_reply)
      reply = "Discus prefer slow water, so turn the pump down or spread the outflow, and keep the tank near thirty degrees."
      posts = [first_post, reply, second_reply, reply, reply].map.with_index do |text, index|
        classes = index.zero? ? "b-post js-comment-entry b-post--first js-conversation-starter" : "b-post js-comment-entry"
        %(<li class="#{classes}"><div class="b-post__body"><p>#{text}</p></div></li>)
      end
      html = '<html><head><meta name="generator" content="vBulletin 6.0.6"><title>New discus setup</title></head>' \
             "<body><main><h1>New discus setup</h1><ul class=\"conversation-list\">#{posts.join}</ul></main></body></html>"
      Nokodown.to_markdown(html)
    end

    it "keeps an opening post whose classes differ from the replies'" do
      markdown = thread("I am setting up a discus tank that held goldfish, with a sump, and wonder whether the pump is too strong.", "Agreed.")

      markdown.should include("wonder whether the pump is too strong")
      markdown.should include("keep the tank near thirty degrees")
    end

    it "keeps a reply with several links" do
      reply = 'Fit <a href="https://shop.example/ball-valve">a ball valve on the return line</a> or ' \
              '<a href="https://shop.example/pump-2000">a smaller return pump</a>, as I did last spring.'
      markdown = thread("I am setting up a discus tank that held goldfish, with a sump, and wonder whether the pump is too strong.", reply)

      markdown.should include("as I did last spring")
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

# frozen_string_literal: true

RSpec.describe Nokodown::ProductReviews do
  def markdown(head, main)
    Nokodown.to_markdown("<html><head>#{head}</head><body><main>#{main}</main></body></html>", url: "https://example.com/p")
  end

  let(:product_type) { '<script type="application/ld+json">{"@type": "Product", "name": "Field Notebook"}</script>' }
  let(:paragraph) do
    "<p>A pocket notebook with 96 pages of dot-grid paper, a waterproof cover and a lay-flat binding, sewn to survive " \
      "a season of field work and sized to fit the back pocket of a pair of jeans. The paper is acid-free and takes " \
      "ink, pencil and wax crayon.</p>"
  end
  let(:description) { "<h1>Field Notebook</h1>#{paragraph}" }
  let(:details) do
    "<p>Each notebook ships with a spare elastic band, a pencil loop and a pocket inside the back cover for receipts " \
      "and maps. The dot grid is printed in a pale grey that stays out of the way of your notes and disappears from " \
      "photocopies and scans of the pages.</p>"
  end
  let(:reviews) do
    '<div id="reviews"><h2>Reviews</h2><div class="review-item"><p>It survived a whole summer of surveys in my back ' \
      "pocket, and the paper takes pencil and fountain pen alike without any bleeding through the page.</p></div></div>"
  end
  let(:product_box) { '<div itemscope itemtype="https://schema.org/Product"><span itemprop="name">Field Notebook</span></div>' }
  let(:cart_form) { '<form action="/cart/add"><button>Add to cart</button></form>' }
  let(:verdict) do
    '<div class="review-summary"><h2>Verdict</h2><p>The sturdiest pocket notebook we tested this year, ' \
      "and the only one whose binding did not crack after a month of daily use in the field.</p></div>"
  end

  it "finds shops that declare no product type by their cart form" do
    result = markdown("", "#{description}#{cart_form}#{reviews}")

    result.should include("dot-grid paper")
    result.should_not include("summer of surveys")
  end

  it "finds shops that declare no product type by their Product microdata" do
    result = markdown("", "#{description}#{product_box}#{reviews}")

    result.should include("dot-grid paper")
    result.should_not include("summer of surveys")
  end

  it "removes schema.org reviews even though each has a description of its own" do
    review = '<div itemprop="review" itemscope itemtype="https://schema.org/Review"><p itemprop="description">' \
             "Bought three of these for my survey team and every one of them made it through a wet season of work.</p></div>"
    result = markdown(product_type, "#{description}<div>#{review}</div>")

    result.should include("dot-grid paper")
    result.should_not include("survey team")
  end

  it "keeps editorial reviews, which the seller wrote" do
    editorial = '<div id="editorialReviews"><h2>Editorial reviews</h2><p>"The only notebook that came back from our ' \
                'Arctic trip in one piece." - Expedition Quarterly</p></div>'
    result = markdown(product_type, "#{description}#{editorial}#{reviews}")

    result.should include("Arctic trip")
    result.should_not include("summer of surveys")
  end

  it "keeps critics' quotes in a section named after the description" do
    quotes = '<div class="product-description" id="press-reviews"><h2>Reviews</h2><p>"Tough enough for a month ' \
             'in the rainforest." - Field Gear Monthly</p></div>'
    result = markdown(product_type, "#{description}#{quotes}#{reviews}")

    result.should include("month in the rainforest")
    result.should_not include("summer of surveys")
  end

  it "keeps testimonials on a service page that declares a product" do
    testimonials = '<section class="testimonials"><div class="review-card"><p>Their crew cleared the wasps from our ' \
                   "attic in an afternoon and came back a week later to check that the nest had not been rebuilt.</p></div></section>"
    markdown(product_type, "#{description}#{testimonials}").should include("cleared the wasps")
  end

  it "keeps reviews on pages that are not product pages" do
    head = '<meta property="og:type" content="article">'
    result = markdown(head, "#{description}#{verdict}")

    result.should include("sturdiest pocket notebook")
  end

  it "keeps reviews on an article that embeds a product box or a cart form" do
    head = '<script type="application/ld+json">{"@type": "BlogPosting", "headline": "Field Notebook review"}</script>'
    [product_box, cart_form].each do |embed|
      markdown(head, "#{description}#{embed}#{verdict}").should include("sturdiest pocket notebook")
    end
  end

  it "keeps the title and description when a wrapper around them is named after the reviews" do
    around_title = %(<div class="yotpo-main">#{description}#{reviews}</div>)
    around_description = %(<h1>Field Notebook</h1><div class="yotpo-main"><div itemprop="description">#{paragraph}</div>#{reviews}</div>)
    [around_title, around_description].each do |main|
      result = markdown(product_type, "#{main}#{details}")

      result.should include("dot-grid paper")
      result.should_not include("summer of surveys")
    end
  end

  it "keeps wrappers whose class only says that the product has reviews" do
    names = ["product-main has-reviews", "product--no-reviews", "with-reviews", "reviews-enabled", "category-reviews", "tag-reviews"]
    names.each do |name|
      result = markdown(product_type, %(<h1>Field Notebook</h1><div class="#{name}">#{paragraph}</div>#{details}#{reviews}))

      result.should include("dot-grid paper")
      result.should_not include("summer of surveys")
    end
  end

  it "does not take a word that contains a vendor's prefix for its widget" do
    ["juniper-product-info", "timestamped-notes"].each do |name|
      result = markdown(product_type, %(<h1>Field Notebook</h1><div class="#{name}">#{paragraph}</div>#{details}))

      result.should include("dot-grid paper")
    end
  end

  it "keeps the reviews when they are all the page has" do
    markdown(product_type, "<h1>Field Notebook reviews</h1>#{reviews}").should include("summer of surveys")
  end
end

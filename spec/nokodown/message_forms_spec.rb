# frozen_string_literal: true

RSpec.describe Nokodown::MessageForms do
  def markdown(html, url: "https://www.example.com/blog/lake-trip")
    Nokodown.to_markdown("<html><body>#{html}</body></html>", url: url, title: false)
  end

  def story
    "<h1>Lake trip</h1><p>#{'We walked around the lake at dawn and saw two herons fishing by the reeds. ' * 3}</p>"
  end

  it "removes comment, review and contact forms with the title above them, in any language" do
    forms = [
      '<div class="box"><h3>Laisser un commentaire</h3><form action="/wp-comments-post.php"><p>Votre adresse e-mail ' \
      'ne sera pas publiée.</p><p><label>Commentaire</label><textarea name="comment"></textarea></p>' \
      '<p>Nom <input name="author"></p></form></div>',
      '<div class="box"><h3>留言框</h3><form><p>您的姓名： <input type="text" name="name"></p>' \
      "<textarea></textarea></form></div>",
      '<div class="box"><h3>Leave a Reply</h3><form><input type="email" name="email"><textarea></textarea></form></div>'
    ]
    forms.each { |form| markdown("<div class=\"post\">#{story}#{form}</div>").should end_with("by the reeds.") }
  end

  it "removes a longer note under the form's title, and a title set in a span named for it" do
    form = '<form><input type="text" name="author"><textarea></textarea></form>'
    boxes = [
      "<div class=\"box\"><h3>Kontakta oss</h3><p>Write your details below and we will call you back within a day.</p>" \
      "#{form}</div>",
      "<div class=\"box\"><span class=\"comment-reply-title\">Be the first to review “Trail kettle, two litres”</span>" \
      "#{form}</div>"
    ]
    boxes.each { |box| markdown("<div class=\"post\">#{story}#{box}</div>").should end_with("by the reeds.") }
  end

  it "keeps the reply that a reply form follows" do
    reply = '<div class="answer"><p>Mine reopened on Monday, once the floods had gone down.</p>' \
            '<form><p>Your email address will not be published.</p><input type="text" name="author">' \
            "<textarea></textarea></form></div>"

    markdown("<div class=\"post\">#{story}#{reply}</div>").should end_with("once the floods had gone down.")
  end

  it "keeps a form that ASP.NET wraps the page in, or one that holds the page's title" do
    wrapped = '<form id="aspnetForm"><h2>Opening hours</h2><p>We open at nine and close at six, also on holidays.</p>' \
              '<input type="text" name="name"><textarea></textarea></form>'
    titled = '<div class="content"><form><h1>Contact Us</h1><p>18 High Street, Watton, Thetford</p>' \
             '<input type="text" name="name"><textarea></textarea></form></div>'

    markdown(wrapped).should include("We open at nine")
    markdown(titled).should include("18 High Street")
  end

  it "keeps the verses and pictures in a form whose text boxes are hidden" do
    verses = '<p>Ek roz baazi yun saze, sheesha tera to patthar mera ho.</p><img src="/rose.jpg" alt="Rose">' \
             '<p>Takdeer banane wale, tune bhi had kar di.</p>'
    html = "<div class=\"post-body\"><form name=\"picForm\">#{verses}<input type=\"text\" name=\"line\">" \
           '<textarea style="visibility: hidden"></textarea></form></div>'

    markdown(html).should include("tune bhi had kar di")
  end

  it "keeps a product's order form, though it asks for a note" do
    html = "#{story}<form class=\"cart\"><p>Flavour: Vanilla or Red Velvet (AED30.00)</p><p>Cakes need 3 days' notice.</p>" \
           '<input type="text" name="name_on_cake"><textarea name="message"></textarea>' \
           '<input type="number" name="quantity"></form>'

    markdown(html).should include("Cakes need 3 days' notice.")
  end

  it "keeps the e-mail address or phone number beside or inside a contact form" do
    beside = '<div class="box"><p>Use the form below or write to ads@example.com.</p>' \
             '<form><input type="text" name="name"><textarea></textarea></form></div>'
    inside = '<div class="call"><form><p>Or call us on 0800 123 4567.</p><input type="text" name="name">' \
             "<textarea></textarea></form></div>"

    markdown("#{story}#{beside}").should include("ads@example.com")
    markdown("#{story}#{inside}").should include("0800 123 4567")
  end

  it "keeps the form that an application page's main region holds" do
    html = "<main><h1>Apply for the March course</h1><form><p>Fields in bold must be filled in, in Latin letters.</p>" \
           "<label>Name</label><input name=\"name\"><textarea name=\"note\"></textarea></form></main>"

    markdown(html).should include("Fields in bold must be filled in")
  end

  it "keeps the table of what an inquiry form asks about" do
    html = "#{story}<div class=\"inquiry\"><form><table><tr><th>Property</th><th>Type</th><th>Address</th></tr>" \
           '<tr><td><input type="hidden" name="id" value="6136">F.L.A.G.</td><td>Apartment</td><td>Minatomachi, Sanyo-Onoda</td></tr>' \
           '</table><table><tr><th>Name</th><td><input type="text" name="name"></td></tr></table><textarea></textarea></form></div>'

    markdown(html).should include("Minatomachi")
  end

  it "keeps a contact page that holds nothing but its form" do
    html = '<div id="center"><form><p>Please do not write to us about SEO services.</p><input type="text" name="email">' \
           "<textarea></textarea></form></div>"

    markdown(html, url: "https://www.example.com/contact.php").should include("Please do not write to us")
  end
end

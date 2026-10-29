# frozen_string_literal: true

RSpec.describe "UI labels" do
  let(:text) { "<p>The stove boils a litre in three minutes.</p>" }

  it "drops paragraphs that are only the label of a control, in the major web languages" do
    labels = ["Leer más »", "Загрузка ...", "Voltar ao topo", "MENU", "Cantidad:", "加入购物车", "Быстрый просмотр", "+更多", "Zum Inhalt springen"]
    convert(labels.map { |label| "<p>#{label}</p>" }.join + text).should == "The stove boils a litre in three minutes."
  end

  it "drops a read-more link after an excerpt in any of those languages" do
    convert("<p>Der Kocher kocht einen Liter in drei Minuten … <a href='/kocher'>Weiterlesen →</a></p>").should ==
      "Der Kocher kocht einen Liter in drei Minuten …"
  end

  it "keeps the same words inside a sentence and as a heading" do
    html = "<h2>Menu</h2><p>Order <a href='/more'>more</a> fuel, or <a href='/info'>learn more</a> about it.</p>"
    convert(html).should == "## Menu\n\nOrder [more](https://example.com/more) fuel, or [learn more](https://example.com/info) about it."
  end
end

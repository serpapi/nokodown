# frozen_string_literal: true

RSpec.describe "UI labels" do
  let(:text) { "<p>The stove boils a litre in three minutes.</p>" }

  it "drops paragraphs that are only the label of a control, in the major web languages" do
    labels = ["Leer más »", "Загрузка ...", "Voltar ao topo", "MENU", "Cantidad:", "加入购物车", "Быстрый просмотр", "+更多", "Zum Inhalt springen"]
    convert(labels.map { |label| "<p>#{label}</p>" }.join + text).should == "The stove boils a litre in three minutes."
  end

  it "keeps a read-more link that is the only way to its page" do
    convert("<h3>Kocher im Test</h3><p>Er kocht einen Liter in drei Minuten …</p><p><a href='/kocher'>Weiterlesen</a></p>").should ==
      "### Kocher im Test\n\nEr kocht einen Liter in drei Minuten …\n\n[Weiterlesen](https://example.com/kocher)"
  end

  it "keeps the same words inside a sentence and as a heading" do
    html = "<h2>Menu</h2><p>Order <a href='/more'>more</a> fuel, or <a href='/info'>learn more</a> about it.</p>"
    convert(html).should == "## Menu\n\nOrder [more](https://example.com/more) fuel, or [learn more](https://example.com/info) about it."
  end
end

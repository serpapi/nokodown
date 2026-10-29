# frozen_string_literal: true

module Nokodown
  module Markdown
    # Characters sites put between inline items (" | ", " · ", " / ") and
    # glyphs they put on links (arrows, chevrons, close and edit marks). Line
    # breaks and link brackets already set the items apart.
    module Separators
      MARKS = "|·•‧∙"
      GLYPHS = "#{MARKS}\u2190-\u21FF\u2794-\u27BF\u27F5-\u27FF\u25B2-\u25C5✕✖✎✏"
      LINK_EDGES = /\A[\s#{GLYPHS}]+|[\s#{GLYPHS}]+\z/.freeze
      # Guillemets are quotation marks too; only an unpaired one is a chevron.
      CHEVRONS = [[/\A[\s«‹]+/, /[»›]/], [/[\s»›]+\z/, /[«‹]/]].freeze
      LINE_EDGES = /\A(?:\|\s*)+|(?:\s*[#{MARKS}])+\z/.freeze
      BETWEEN_LINKS = %r{(?<=\))\s+[#{MARKS}/]\s+(?=!?\[)}.freeze
      REPEATED = /(\s[#{MARKS}])(?:\s+[#{MARKS}])+(?=\s)/.freeze
      # Nothing but punctuation and operators: "|", "~", "- ->". Emoji,
      # emoticons and currency signs say something.
      SYMBOL_LINE = /\A[\p{P}\p{Sm}\s]*\z/.freeze
      EMOTICON = %r{\A[:;=][-'^]?[()\[\]/\\|*]+\z}.freeze

      module_function

      def link_text(text)
        text = text.gsub(LINK_EDGES, "")
        CHEVRONS.reduce(text) { |stripped, (edge, pair)| stripped.match?(pair) ? stripped : stripped.sub(edge, "") }
      end

      # The line without separators that separate nothing, or nil when only
      # symbols are left.
      def line(line)
        line = line.gsub(REPEATED, '\1').gsub(BETWEEN_LINKS, " ").gsub(LINE_EDGES, "")
        line if !line.match?(SYMBOL_LINE) || line.match?(EMOTICON)
      end
    end
  end
end

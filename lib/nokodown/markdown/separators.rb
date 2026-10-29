# frozen_string_literal: true

module Nokodown
  module Markdown
    # Characters sites put between inline items (" | ", " · ", " / ") and
    # glyphs they put on links (arrows, chevrons, close and edit marks). Line
    # breaks and link brackets already set the items apart.
    module Separators
      MARKS = "|·•‧∙"
      GLYPHS = "#{MARKS}\u2190-\u21FF\u2794-\u27BF\u27F5-\u27FF\u25B2-\u25C5✕✖✎✏"
      # Runs at the start of a text, matched on the reversed text for its
      # end: Ruby would retry a pattern anchored at the end from every start.
      LINK_EDGE = /\A[\s#{GLYPHS}]+/.freeze
      # Guillemets are quotation marks too; only an unpaired one is a chevron.
      OPENING_CHEVRONS = /\A[\s«‹]+/.freeze
      CLOSING_CHEVRONS = /\A[\s»›]+/.freeze
      LINE_START = /\A(?:\|\s*)+/.freeze
      LINE_END = /\A(?:[#{MARKS}]\s*)+/.freeze
      BETWEEN_LINKS = %r{(?<=\))\s+[#{MARKS}/]\s+(?=!?\[)}.freeze
      REPEATED = /(\s[#{MARKS}])(?:\s+[#{MARKS}])+(?=\s)/.freeze
      # Nothing but punctuation and operators: "|", "~", "- ->". Emoji,
      # emoticons and currency signs say something.
      SYMBOL_LINE = /\A[\p{P}\p{Sm}\s]*\z/.freeze
      EMOTICON = %r{\A[:;=][-'^]?[()\[\]/\\|*]+\z}.freeze

      module_function

      def link_text(text)
        text = trim_end(text.sub(LINK_EDGE, ""), LINK_EDGE)
        text = text.sub(OPENING_CHEVRONS, "") unless text.match?(/[»›]/)
        text.match?(/[«‹]/) ? text : trim_end(text, CLOSING_CHEVRONS)
      end

      # The line without separators that separate nothing, or nil when only
      # symbols are left.
      def line(line)
        line = line.gsub(REPEATED, '\1').gsub(BETWEEN_LINKS, " ")
        line = trim_end(line.sub(LINE_START, ""), LINE_END)
        line if !line.match?(SYMBOL_LINE) || line.match?(EMOTICON)
      end

      def trim_end(text, run)
        tail = text.reverse[run]
        tail ? text.delete_suffix(tail.reverse) : text
      end
    end
  end
end

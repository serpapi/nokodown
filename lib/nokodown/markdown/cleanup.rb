# frozen_string_literal: true

module Nokodown
  module Markdown
    # Block-level tidying after rendering: repeated blocks, stray rules,
    # punctuation-only lines, section headings left without a section, and
    # redundant or repeated images. Converting the whole page (full), or a
    # selection of it, keeps everything but punctuation-only lines: what
    # repeats, boilerplate lines, symbols such as rating stars, rules and
    # headings without a section can all be what was selected.
    module Cleanup
      DEDUPE_WINDOW = 4
      IMAGE_ONLY = /\A!\[([^\]]*)\]\([^)]*\)\z/.freeze
      LINKED_HEADING = /\A#+ \[.*\]\(.*\)\z/.freeze
      TITLE_LIST_MIN = 3
      QUOTE_GRAM = 6
      REPEATED_BLOCK_MIN = 100
      REPEATED_RUN_MIN = 2
      REPEATED_QUOTE_SHARE = 0.5
      QUOTE_OPENING = 12
      # Not before a lowercase word or a number, as after "e.g." or "v.".
      # Matched from the first mark of a run and without backtracking, so a long
      # run of dots is not rescanned from each one on Ruby 2.7.
      SENTENCE_END = /(?<![.!?…])[.!?…]++["'”’)\]*_]*+(?=\s+[^\p{Ll}\p{N}]|\s*\z)/.freeze
      # From where the last sentence ended through the end of the next one.
      SENTENCE = /\G.*?#{SENTENCE_END}/m.freeze
      # What makes a line more than stray punctuation when converting the
      # whole page: a letter, a digit or a symbol such as a rating star.
      WORD_OR_SYMBOL = /[\p{L}\p{N}\p{So}]/.freeze

      module_function

      # images: the Renderer's rendered_images.
      def call(blocks, images = {}, full: false)
        return blocks.reject { |block| punctuation?(block) } if full

        blocks = blocks.reject { |block| noise?(block) }
        blocks = dedupe(blocks)
        blocks = drop_repeated_runs(blocks)
        blocks = shorten_repeated_quotes(blocks)
        blocks = trim_rules(blocks)
        blocks = drop_empty_sections(blocks)
        images.empty? ? blocks : ImageCleanup.new(images).call(blocks)
      end

      # Separators and stray marks ("•", "...", a zero-width joiner).
      def punctuation?(block)
        block.kind == :paragraph && !block.text.match?(WORD_OR_SYMBOL) && !block.text.include?("](")
      end

      def noise?(block)
        return false unless block.kind == :paragraph

        text = block.text
        return true unless text.match?(/[\p{L}\p{N}]/) || text.include?("](")

        plain = text.gsub(/[*_`~]/, "").strip
        plain.length <= 80 && plain.match?(Patterns::BOILERPLATE_TEXT)
      end

      # Responsive and "enlarge" variants repeat an image (and its caption) a
      # block or two later, within the same section. Dropping the image makes
      # the captions adjacent.
      def dedupe(blocks)
        blocks.each_with_object([]) do |block, kept|
          window = block.text.match?(IMAGE_ONLY) ? same_section(kept.last(DEDUPE_WINDOW)) : kept.last(1)
          kept << block unless window.any? { |previous| identity(previous) == identity(block) }
        end
      end

      def drop_repeated_runs(blocks)
        seen = Set.new
        repeated = blocks.map { |block| repeatable?(block) && !seen.add?(block.text) }
        return blocks unless repeated.include?(true)

        runs = blocks.each_index.chunk_while { |a, b| repeated[a] && repeated[b] }
        dropped = runs.select { |run| run.size >= REPEATED_RUN_MIN }.flatten.to_set
        blocks.reject.with_index { |_, index| dropped.include?(index) }
      end

      def repeatable?(block)
        block.text.length >= REPEATED_BLOCK_MIN && block.kind != :heading && block.kind != :code
      end

      # A reply that quotes a post shown earlier keeps the quote's opening, so
      # the reader still sees which point it answers. Only posts count as the
      # source: a quote like an earlier quote is the page's own repetition.
      def shorten_repeated_quotes(blocks)
        last_quote = blocks.rindex { |block| block.kind == :quote }
        return blocks unless last_quote

        seen = Set.new
        checked = blocks.first(last_quote + 1).map do |block|
          grams = word_grams(block.text)
          next(repeated?(grams, seen) ? quote_opening(block) : block) if block.kind == :quote

          seen.merge(grams)
          block
        end
        checked + blocks.drop(last_quote + 1)
      end

      def repeated?(grams, seen)
        !grams.empty? && grams.count { |gram| seen.include?(gram) } >= grams.size * REPEATED_QUOTE_SHARE
      end

      # A quote with fewer than QUOTE_OPENING words beyond its opening is cheap
      # context and stays whole. The opening drops links and images: the post
      # above has them.
      def quote_opening(block)
        lines = block.text.split("\n").map { |line| line.sub(/\A> ?/, "") }
        own = lines.reject { |line| line.start_with?(">") }.take_while { |line| !line.match?(/\A(?:`{3,}[^`]*|~~~.*)\z/) }
        opening = squeeze_blank(opening_lines(own.map { |line| Text.unlink(line).strip }))
        return block if opening.empty? || words(block.text).size - words(opening.join(" ")).size < QUOTE_OPENING

        opening[-1] += " …"
        Block.new(:quote, opening.map { |line| line.empty? ? ">" : "> #{line}" }.join("\n"))
      end

      # The quoter's own lines up to the sentence that reaches QUOTE_OPENING
      # words, or to the end of a paragraph that brings it to half of that.
      # Lead-in lines ("Sam said:") do not count.
      def opening_lines(lines)
        count = 0
        lines.each_with_object([]) do |line, opening|
          sentence = line.match?(SENTENCE_END)
          next opening << line if line.end_with?(":") && !sentence

          size = words(line).size
          break opening << sentence_head(line, QUOTE_OPENING - count) if count + size >= QUOTE_OPENING
          break opening << line if sentence && count + size >= QUOTE_OPENING / 2

          opening << line
          count += size
        end
      end

      def squeeze_blank(lines)
        lines = lines.chunk_while { |a, b| a.empty? && b.empty? }.map(&:first)
        lines.shift while lines.first&.empty?
        lines.pop while lines.last&.empty?
        lines
      end

      # The line up to the first sentence end after `needed` words, never
      # inside brackets or code, closing bold it cuts; the whole line when
      # there is none. The head grows a sentence at a time, so a line of many
      # short sentences is read once rather than once per sentence.
      def sentence_head(line, needed)
        head = +""
        uncounted = +""
        size = open_brackets = ticks = 0
        line.scan(SENTENCE) do |sentence|
          head << sentence
          uncounted << sentence
          open_brackets += sentence.count("[") - sentence.count("]")
          ticks += sentence.count("`")
          next unless open_brackets.zero? && ticks.even?

          # Counted once its brackets close, so a link that spans sentences is read whole.
          size += words(uncounted).size
          uncounted.clear
          next if size < needed

          return head.scan("**").size.odd? ? "#{head}**" : head
        end
        line
      end

      def word_grams(text)
        words(text.downcase).each_cons(QUOTE_GRAM).map(&:hash)
      end

      def words(text)
        Text.plain(text).scan(/[[:word:]]+/)
      end

      def same_section(blocks)
        heading = blocks.rindex { |block| block.kind == :heading }
        heading ? blocks.drop(heading + 1) : blocks
      end

      # Variants of one image differ in URL (size, crop) but share alt text.
      def identity(block)
        alt = block.text[IMAGE_ONLY, 1]
        alt && alt.length >= 10 ? "image:#{alt}" : block.text
      end

      def trim_rules(blocks)
        blocks = blocks.each_with_object([]) do |block, kept|
          next if block.kind == :rule && (kept.empty? || kept.last.kind == :rule || kept.last.kind == :heading)

          kept << block
        end
        blocks.pop while blocks.last&.kind == :rule
        blocks
      end

      # A heading followed by nothing, or by a heading at the same or a higher
      # level, lost its section during extraction. Title lists are content in
      # their own right, and a page that is only its headline keeps it.
      def drop_empty_sections(blocks)
        titles = title_list_indexes(blocks)
        kept = blocks.each_index.reject { |index| !titles.include?(index) && empty_section?(blocks, index) }
        kept.pop while kept.any? && blocks[kept.last].kind == :heading && !titles.include?(kept.last)
        return blocks.values_at(*kept) if kept.any?

        h1 = blocks.find { |block| block.kind == :heading && block.level == 1 }
        return [] if h1.nil?

        # A page of nothing but headings under its headline is its outline.
        blocks.all? { |block| block.kind == :heading } ? blocks : [h1]
      end

      def empty_section?(blocks, index)
        block = blocks[index]
        return false unless block.kind == :heading

        following = blocks[(index + 1)..].find { |b| b.kind != :rule }
        return true if following.nil?
        return false unless following.kind == :heading && following.level <= block.level

        heading_text(block).match?(Patterns::NOISE_HEADING)
      end

      # Same-level headings in a row, mostly links, are the titles of cards
      # whose details were removed (products, related guides), not sections.
      # A "Trending" or "Related" heading among them is still a section label.
      def title_list_indexes(blocks)
        runs = blocks.each_index.reject { |index| blocks[index].kind == :rule }.slice_when do |a, b|
          blocks[a].kind != :heading || blocks[b].kind != :heading || blocks[a].level != blocks[b].level
        end
        indexes = runs.select { |run| title_list?(blocks.values_at(*run)) }.flatten
        indexes.reject { |index| heading_text(blocks[index]).match?(Patterns::NOISE_HEADING) }.to_set
      end

      def title_list?(headings)
        return false if headings.size < TITLE_LIST_MIN

        headings.count { |heading| heading.text.match?(LINKED_HEADING) } * 2 > headings.size
      end

      def heading_text(block)
        block.text.sub(/\A#+\s*/, "").gsub(/\[([^\]]*)\]\([^)]*\)/, '\1').gsub(/[*_`]/, "")
      end
    end
  end
end

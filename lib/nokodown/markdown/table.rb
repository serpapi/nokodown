# frozen_string_literal: true

module Nokodown
  module Markdown
    # Data tables become GFM tables; layout tables are unwrapped into the
    # blocks they hold.
    class Table
      MAX_COLSPAN = 50
      MAX_ROWSPAN = 500
      MAX_NAME = 80
      NAMED_ROWS = 0.8
      LINK_OR_IMAGE = /\A!?\[/.freeze

      def initialize(renderer, node)
        @renderer = renderer
        @node = node
      end

      def blocks
        return layout_blocks unless Tables.data_table?(@node)

        grid, spanning = trimmed_grid
        return caption + [Block.new(:list, name_values(grid))] if grid.size >= 2 && names?(grid) && !header_row?

        titles = title_rows(grid, spanning)
        notes = note_rows(grid, spanning)
        return layout_blocks if grid.size < 2 || grid.first.size < 2

        caption + titles + [Block.new(:table, gfm(grid))] + notes
      end

      private

      def gfm(grid)
        lines = grid.map { |row| "| #{row.join(' | ')} |" }
        lines.insert(1, "| #{Array.new(grid.first.size, '---').join(' | ')} |")
        lines.join("\n")
      end

      # A first row with one cell across the table is its title; the next row
      # holds the column names.
      def title_rows(grid, spanning)
        titles = []
        while grid.size > 2 && spanning.first && grid.first.first != ""
          spanning.shift
          titles << Block.new(:paragraph, Text.escape_line_starts(grid.shift.first.gsub("\\|", "|")))
        end
        titles
      end

      # Rows across the table at its end hold a note or the text of a post
      # laid out in a table, which go below it as the blocks they hold.
      def note_rows(grid, spanning)
        notes = []
        while grid.size > 1 && spanning.last && grid.last.first != ""
          grid.pop
          notes.unshift(*spanning.pop)
        end
        notes
      end

      # GFM takes a table's first row for its column names, which a table of
      # names and values does not have ("Weight | 3 kg"): each row is a line
      # of the list instead, and a row across the table, which names the
      # rows below it, stays in its place.
      def name_values(grid)
        grid.map { |row| "- #{name_value(*row.map { |cell| Dom.squish(cell.gsub("\\|", "|")) })}" }.join("\n")
      end

      # Names are short text, not pictures or links: two columns of those
      # are a grid.
      def names?(grid)
        return false unless grid.first.size == 2

        names = grid.map(&:first).reject(&:empty?)
        names.size >= grid.size * NAMED_ROWS && names.all? { |name| name.length <= MAX_NAME && !name.match?(LINK_OR_IMAGE) }
      end

      def name_value(name, value)
        return "#{name}#{value}" if name.empty? || value.empty?

        name.match?(/[:：]\z/) ? "#{name} #{value}" : "#{name}: #{value}"
      end

      # Column names sit in a <thead> or in a row of <th> cells, perhaps below
      # a title row.
      def header_row?
        rows = Tables.rows(@node).reject { |row| row.content.strip.empty? }.first(2)
        rows.any? { |row| row.parent.name == "thead" || Tables.cells(row).all? { |cell| cell.name == "th" } }
      end

      def caption
        node = @node.at_css("caption")
        text = node ? Text.single_line(@renderer.inline(node.children)) : ""
        text.empty? ? [] : [Block.new(:paragraph, text)]
      end

      # Drops empty rows, empty and separator columns and pads short rows;
      # and for each row that is one cell across the table, that cell's
      # blocks.
      def trimmed_grid
        grid, spanning = cell_grid
        kept = grid.each_index.reject { |index| grid[index].all?(&:empty?) }
        grid = grid.values_at(*kept)
        width = grid.map(&:size).max.to_i
        grid.each { |row| row.fill("", row.size...width) }
        columns = (0...width).select { |column| grid.any? { |row| !row[column].empty? } && !separator?(grid, column) }
        [grid.map { |row| row.values_at(*columns) }, spanning.values_at(*kept)]
      end

      # A column of one sign in every row, its header too (":" between a label
      # and its value, "-" between two teams), only parts its neighbours.
      def separator?(grid, column)
        values = grid.map { |row| row[column] }.reject(&:empty?).uniq
        values.size == 1 && values.first.match?(Separators::SYMBOL_LINE)
      end

      # One value per row and column: a rowspan repeats its value in the rows
      # below, a colspan leaves the extra columns blank.
      def cell_grid
        spans = {}
        rows = Tables.rows(@node)
        blocks = []
        grid = rows.map do |row|
          line = spans.transform_values(&:first)
          spans = spans.transform_values { |text, rows_left| [text, rows_left - 1] }.reject { |_, (_, rows_left)| rows_left.zero? }
          blocks << place_cells(row, line, spans)
          (0..(line.keys.max || -1)).map { |column| line.fetch(column, "") }
        end
        width = grid.map(&:size).max.to_i
        [grid, rows.each_index.map { |index| blocks[index].first if spanning?(rows[index], width) }]
      end

      def spanning?(row, width)
        cells = Tables.cells(row)
        width > 1 && cells.size == 1 && span(cells.first, "colspan", MAX_COLSPAN) >= width
      end

      # The blocks of each cell.
      def place_cells(row, line, spans)
        column = 0
        Tables.cells(row).map do |cell|
          column += 1 while line.key?(column)
          blocks = @renderer.cell_blocks(cell)
          text = Emphasis.unwrap(Emphasis.merge(cell_text(blocks)))
          text = Text.table_cell(Text.unescape_lone(text))
          rows = span(cell, "rowspan", MAX_ROWSPAN)
          span(cell, "colspan", MAX_COLSPAN).times do |offset|
            value = offset.zero? ? text : ""
            line[column + offset] = value
            spans[column + offset] = [value, rows - 1] if rows > 1
          end
          column += 1 while line.key?(column)
          blocks
        end
      end

      # A heading's markers mean nothing in a cell.
      def cell_text(blocks)
        blocks.map(&:content).join(" ")
      end

      def span(cell, attribute, limit)
        cell[attribute].to_i.clamp(1, limit)
      end

      # A row of inline cells reads as one line; rows holding blocks are
      # rendered cell by cell.
      def layout_blocks
        Labels.siblings(Tables.rows(@node).map do |row|
          cells = Tables.cells(row).reject { |cell| cell.content.strip.empty? && cell.at_css("img").nil? }
          if cells.none? { |cell| @renderer.contains_block?(cell) }
            @renderer.text_paragraphs(cells.map { |cell| @renderer.inline(cell.children) }.join(" "))
          else
            cells.flat_map { |cell| @renderer.children_blocks(cell) }
          end
        end.reject(&:empty?))
      end
    end
  end
end

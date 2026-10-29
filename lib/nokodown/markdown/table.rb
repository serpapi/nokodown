# frozen_string_literal: true

module Nokodown
  module Markdown
    # Data tables become GFM tables; layout tables are unwrapped into the
    # blocks they hold.
    class Table
      MAX_COLSPAN = 50
      MAX_ROWSPAN = 500

      def initialize(renderer, node)
        @renderer = renderer
        @node = node
      end

      def blocks
        return layout_blocks unless Tables.data_table?(@node)

        grid, spanning = trimmed_grid
        titles = title_rows(grid, spanning)
        return layout_blocks if grid.size < 2 || grid.first.size < 2

        caption + titles + [Block.new(:table, gfm(grid))]
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

      def caption
        node = @node.at_css("caption")
        text = node ? Text.single_line(@renderer.inline(node.children)) : ""
        text.empty? ? [] : [Block.new(:paragraph, text)]
      end

      # Drops empty rows, empty and separator columns and pads short rows;
      # and whether each row is one cell across the table.
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
        grid = rows.map do |row|
          line = spans.transform_values(&:first)
          spans = spans.transform_values { |text, rows_left| [text, rows_left - 1] }.reject { |_, (_, rows_left)| rows_left.zero? }
          place_cells(row, line, spans)
          (0..(line.keys.max || -1)).map { |column| line.fetch(column, "") }
        end
        width = grid.map(&:size).max.to_i
        [grid, rows.map { |row| spanning?(row, width) }]
      end

      def spanning?(row, width)
        cells = Tables.cells(row)
        width > 1 && cells.size == 1 && span(cells.first, "colspan", MAX_COLSPAN) >= width
      end

      def place_cells(row, line, spans)
        column = 0
        Tables.cells(row).each do |cell|
          column += 1 while line.key?(column)
          text = Emphasis.unwrap(Emphasis.merge(@renderer.cell_blocks(cell).map(&:text).join(" ")))
          text = Text.table_cell(Text.unescape_lone(text))
          rows = span(cell, "rowspan", MAX_ROWSPAN)
          span(cell, "colspan", MAX_COLSPAN).times do |offset|
            value = offset.zero? ? text : ""
            line[column + offset] = value
            spans[column + offset] = [value, rows - 1] if rows > 1
          end
          column += 1 while line.key?(column)
        end
      end

      def span(cell, attribute, limit)
        cell[attribute].to_i.clamp(1, limit)
      end

      # A row of inline cells reads as one line; rows holding blocks are
      # rendered cell by cell.
      def layout_blocks
        Tables.rows(@node).flat_map do |row|
          cells = Tables.cells(row).reject { |cell| cell.content.strip.empty? && cell.at_css("img").nil? }
          if cells.none? { |cell| @renderer.contains_block?(cell) }
            @renderer.text_paragraphs(cells.map { |cell| @renderer.inline(cell.children) }.join(" "))
          else
            cells.flat_map { |cell| @renderer.children_blocks(cell) }
          end
        end
      end
    end
  end
end

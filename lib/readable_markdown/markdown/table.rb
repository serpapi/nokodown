# frozen_string_literal: true

module ReadableMarkdown
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

        grid = trimmed_grid
        return layout_blocks if grid.size < 2 || grid.first.size < 2

        caption + [Block.new(:table, gfm(grid))]
      end

      private

      def gfm(grid)
        lines = grid.map { |row| "| #{row.join(' | ')} |" }
        lines.insert(1, "| #{Array.new(grid.first.size, '---').join(' | ')} |")
        lines.join("\n")
      end

      def caption
        node = @node.at_css("caption")
        text = node ? Text.single_line(@renderer.inline(node.children)) : ""
        text.empty? ? [] : [Block.new(:paragraph, text)]
      end

      # Drops empty rows and columns and pads short rows.
      def trimmed_grid
        grid = cell_grid.reject { |row| row.all?(&:empty?) }
        width = grid.map(&:size).max.to_i
        grid.each { |row| row.fill("", row.size...width) }
        columns = (0...width).select { |column| grid.any? { |row| !row[column].empty? } }
        grid.map { |row| row.values_at(*columns) }
      end

      # One value per row and column: a rowspan repeats its value in the rows
      # below, a colspan leaves the extra columns blank.
      def cell_grid
        spans = {}
        Tables.rows(@node).map do |row|
          line = spans.transform_values(&:first)
          spans = spans.transform_values { |text, rows| [text, rows - 1] }.reject { |_, (_, rows)| rows.zero? }
          place_cells(row, line, spans)
          (0..(line.keys.max || -1)).map { |column| line.fetch(column, "") }
        end
      end

      def place_cells(row, line, spans)
        column = 0
        Tables.cells(row).each do |cell|
          column += 1 while line.key?(column)
          text = Text.table_cell(@renderer.children_blocks(cell).map(&:text).join(" "))
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

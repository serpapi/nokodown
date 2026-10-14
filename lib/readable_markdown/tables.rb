# frozen_string_literal: true

module ReadableMarkdown
  module Tables
    module_function

    # Data vs. layout tables, following the checks Firefox uses for
    # accessibility (and Readability copies).
    def data_table?(table)
      return false if table["role"] == "presentation" || table["datatable"] == "0"
      return true if table["summary"].to_s.strip != ""

      caption = table.at_css("caption")
      return true if caption && !caption.content.strip.empty?
      return true if table.at_css("col, colgroup, tfoot, thead, th")
      return false if table.at_css("table")

      rows, columns = size(table)
      return false if rows == 1 || columns == 1 || sparse?(table)
      return true if rows >= 10 || columns > 4

      rows * columns > 10
    end

    # Headerless grids with many blank cells (spacers, indentation) are layout,
    # however many rows they have. Hacker News is the canonical example.
    def sparse?(table)
      cells = table.css("td")
      blank = cells.count { |cell| cell.content.strip.empty? && cell.at_css("img").nil? }
      blank > cells.size * 0.3
    end

    def size(table)
      rows = 0
      columns = 0
      table.css("tr").each do |tr|
        rowspan = tr["rowspan"].to_i
        rows += rowspan.positive? ? rowspan : 1
        cells = tr.css("td").sum do |td|
          colspan = td["colspan"].to_i
          colspan.positive? ? colspan : 1
        end
        columns = cells if cells > columns
      end
      [rows, columns]
    end

    def rows(table)
      table.element_children.flat_map do |child|
        case child.name
        when "tr" then [child]
        when "thead", "tbody", "tfoot" then child.element_children.select { |row| row.name == "tr" }
        else []
        end
      end
    end

    def cells(row)
      row.element_children.select { |cell| cell.name == "td" || cell.name == "th" }
    end
  end
end

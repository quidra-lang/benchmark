module Renderer
  def self.display_line(pieces, slack, alignment, last)
    pieces = pieces.map { |piece| piece.tr('~', ' ') }
    text = pieces.join(' ')
    return text if slack <= 0

    gaps = pieces.length - 1
    if alignment == 'justify' && !last && gaps > 0
      quotient, remainder = slack.divmod(gaps)
      parts = [pieces.first]
      pieces.drop(1).each_with_index do |piece, i|
        parts << ' ' * (quotient + 1 + (i < remainder ? 1 : 0)) << piece
      end
      return parts.join
    end
    return ' ' * slack + text if alignment == 'right'
    return ' ' * (slack / 2) + text if alignment == 'center'

    text
  end

  def self.format_table(rows, columns, caption, number)
    widths = Array.new(columns.length) { |i| rows.map { |row| row[i].length }.max }
    lines = []
    lines << "Table #{number}. #{caption}" unless caption.empty?
    rows.each_with_index do |row, row_index|
      cells = row.each_with_index.map do |text, i|
        missing = widths[i] - text.length
        case columns[i]
        when 'l' then text + ' ' * missing
        when 'r' then ' ' * missing + text
        else
          before = missing / 2
          ' ' * before + text + ' ' * (missing - before)
        end
      end
      lines << cells.join(' | ').sub(/ +\z/, '')
      lines << widths.map { |width| '-' * width }.join('-+-') if row_index.zero?
    end
    lines
  end

  def self.running_head(fields, values, width, serial)
    expanded = fields.map do |field|
      field.gsub(/\{(page|pages|chapter|section)\}/) { values.fetch(Regexp.last_match(1).to_sym) }
    end
    left, center, right = expanded
    left, right = right, left if serial.even?
    line = ' ' * width
    [[0, left], [(width - center.length) / 2, center], [width - right.length, right]].each do |start, text|
      line[start, text.length] = text
    end
    line.sub(/ +\z/, '')
  end

  def self.pages_text(pages)
    lines = pages.flat_map do |page|
      ["--- page #{page[:serial]} ---", page[:header], ''] + page[:body] + ['', page[:footer]]
    end
    lines.map { |line| line + "\n" }.join
  end
end

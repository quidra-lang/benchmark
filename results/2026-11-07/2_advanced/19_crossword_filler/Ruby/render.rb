module Render
  def self.decimal(numerator, denominator, digits = 2)
    scale = 10**digits
    rounded = (2 * numerator * scale + denominator) / (2 * denominator)
    "#{rounded / scale}.#{(rounded % scale).to_s.rjust(digits, '0')}"
  end

  def self.grid_lines(grid, state)
    state.cells.each_slice(grid.width).map(&:join)
  end

  def self.number_lines(grid, layout)
    grid.cells.each_index.each_slice(grid.width).map do |row|
      row.map do |cell|
        if !grid.white?(cell)
          '##'
        elsif layout.numbers[cell]
          layout.numbers[cell].to_s.rjust(2)
        else
          ' .'
        end
      end.join(' ')
    end
  end

  def self.clue_line(slot, state, score, clue, theme)
    word = state.assigned[slot.id]
    if word
      line = "#{slot.number}. #{clue || '(no clue)'} (#{slot.length}) #{word} #{score}"
      line += ' theme' if theme
      line
    else
      "#{slot.number}. (unfilled) (#{slot.length}) #{state.pattern(slot)} -"
    end
  end
end

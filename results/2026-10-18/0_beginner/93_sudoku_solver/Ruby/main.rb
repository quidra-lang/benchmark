rows = [
  '800025000', '070080005', '260400070', '000001900', '010000040',
  '600200000', '900010000', '700000004', '020000036'
]
board = rows.map { |row| row.chars.map(&:to_i) }
placements = 0
solve = lambda do
  empty = nil
  9.times do |row|
    9.times do |column|
      if board[row][column].zero?
        empty = [row, column]
        break
      end
    end
    break if empty
  end
  next true if empty.nil?
  row, column = empty
  solved = false
  (1..9).each do |digit|
    next if board[row].include?(digit) || board.any? { |line| line[column] == digit }
    top, left = row / 3 * 3, column / 3 * 3
    conflict = (top...top + 3).any? do |r|
      (left...left + 3).any? { |c| board[r][c] == digit }
    end
    next if conflict
    board[row][column] = digit
    placements += 1
    if solve.call
      solved = true
      break
    end
    board[row][column] = 0
  end
  solved
end
solve.call
board.each { |row| puts row.join(' ') }
puts "placements: #{placements}"

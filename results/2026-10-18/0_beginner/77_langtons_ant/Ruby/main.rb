size = 11
board = Array.new(size) { Array.new(size, false) }
row = column = 5
direction = 0
directions = [[-1, 0], [0, 1], [1, 0], [0, -1]]
300.times do
  direction = (direction + (board[row][column] ? -1 : 1)) % 4
  board[row][column] = !board[row][column]
  dr, dc = directions[direction]
  row = (row + dr) % size
  column = (column + dc) % size
end
size.times do |r|
  line = size.times.map do |c|
    r == row && c == column ? 'A' : board[r][c] ? '#' : '.'
  end
  puts line.join
end
puts "black: #{board.sum { |line| line.count(true) }}"

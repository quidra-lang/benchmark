grid = ['.......', '..#....', '....#..', '.#.....', '...#.#.', '.......']
paths = lambda do |blocked|
  dp = grid.map { |row| Array.new(row.length, 0) }
  dp[0][0] = 1
  grid.each_index do |row|
    (0...grid[0].length).each do |column|
      if blocked && grid[row][column] == '#'
        dp[row][column] = 0
      elsif row.positive? || column.positive?
        dp[row][column] = (row.positive? ? dp[row - 1][column] : 0) + (column.positive? ? dp[row][column - 1] : 0)
      end
    end
  end
  dp[-1][-1]
end
puts "without obstacles: #{paths.call(false)}"
puts "with obstacles: #{paths.call(true)}"

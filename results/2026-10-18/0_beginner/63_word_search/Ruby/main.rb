board = [
  'MMONKENBIR', 'PMTIGERJPL', 'TGREJEDUZI', 'SPYUTEJDEC', 'WKAPSIDLBN',
  'KUVNGSBPRO', 'RIBSDACBAM', 'YWVAUAPKAH', 'KYCGTHHESR', 'OCCALAOKKR'
]
directions = [
  ['E', 0, 1], ['SE', 1, 1], ['S', 1, 0], ['SW', 1, -1],
  ['W', 0, -1], ['NW', -1, -1], ['N', -1, 0], ['NE', -1, 1]
]
find = lambda do |word|
  found = nil
  board.each_index do |row|
    (0...board[0].length).each do |column|
      directions.each do |name, dr, dc|
        matches = word.chars.each_with_index.all? do |char, i|
          r, c = row + dr * i, column + dc * i
          r.between?(0, board.length - 1) && c.between?(0, board[0].length - 1) && board[r][c] == char
        end
        if matches
          found = "(#{row}, #{column}) #{name}"
          break
        end
      end
      break if found
    end
    break if found
  end
  found || 'not found'
end
%w[TIGER ZEBRA MONKEY PANDA KOALA RABBIT].each { |word| puts "#{word}: #{find.call(word)}" }

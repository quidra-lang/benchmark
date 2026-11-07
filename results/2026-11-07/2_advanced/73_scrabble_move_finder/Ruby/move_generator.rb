require_relative 'board'
require_relative 'scoring'

module MoveGenerator
  LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
  module_function

  def anchors(board)
    return [Board::CENTER].to_set if Board.tiles(board).empty?
    result = Set.new
    Board::SIZE.times do |row|
      Board::SIZE.times do |column|
        result.add([row, column]) if board[row][column] == '.' && Board.neighbors(row, column).any? { |r, c| board[r][c] != '.' }
      end
    end
    result
  end

  def cross_checks(board, trie)
    result = {}
    Board::SIZE.times do |row|
      Board::SIZE.times do |column|
        next unless board[row][column] == '.'
        first, last = row, row
        first -= 1 while first > 0 && board[first - 1][column] != '.'
        last += 1 while last + 1 < Board::SIZE && board[last + 1][column] != '.'
        next if first == last
        prefix = (first...row).map { |r| board[r][column] }.join.upcase
        suffix = ((row + 1)..last).map { |r| board[r][column] }.join.upcase
        result[[row, column]] = LETTERS.chars.select { |letter| trie.include?(prefix + letter + suffix) }.to_set
      end
    end
    result
  end

  def across_moves(board, rack, trie, anchor_squares, checks)
    result = []
    counts = Hash.new(0).merge(rack.chars.tally)
    anchor_squares.sort.each do |row, anchor|
      extend_right = lambda do |node, column, word, start|
        empty = column == Board::SIZE || board[row][column] == '.'
        result << Board::Move.new(row, start, 0, word) if empty && column > anchor && node.terminal
        return if column == Board::SIZE
        unless empty
          letter = board[row][column]
          child = node.children[letter.upcase]
          extend_right.call(child, column + 1, word + letter, start) if child
          return
        end
        allowed = checks[[row, column]]
        node.children.keys.sort.each do |letter|
          next if allowed && !allowed.include?(letter)
          [[letter, letter], ['?', letter.downcase]].each do |tile, written|
            next unless counts[tile] > 0
            counts[tile] -= 1
            extend_right.call(node.children[letter], column + 1, word + written, start)
            counts[tile] += 1
          end
        end
      end
      left_part = lambda do |node, prefix, remaining|
        extend_right.call(node, anchor, prefix, anchor - prefix.size)
        return if remaining == 0
        node.children.keys.sort.each do |letter|
          [[letter, letter], ['?', letter.downcase]].each do |tile, written|
            next unless counts[tile] > 0
            counts[tile] -= 1
            left_part.call(node.children[letter], prefix + written, remaining - 1)
            counts[tile] += 1
          end
        end
      end
      if anchor > 0 && board[row][anchor - 1] != '.'
        first = anchor - 1
        first -= 1 while first > 0 && board[row][first - 1] != '.'
        prefix = board[row][first...anchor].join
        node = trie.prefix(prefix.upcase)
        extend_right.call(node, anchor, prefix, first) if node
      else
        first = anchor - 1
        first -= 1 while first >= 0 && board[row][first] == '.' && !anchor_squares.include?([row, first])
        left_part.call(trie.root, '', anchor - first - 1)
      end
    end
    result
  end

  def generate(board, rack, trie)
    anchor_squares = anchors(board)
    across = across_moves(board, rack, trie, anchor_squares, cross_checks(board, trie))
    transposed = Board.transpose(board)
    down = across_moves(transposed, rack, trie, anchor_squares.map { |r, c| [c, r] }.to_set, cross_checks(transposed, trie))
    moves = across + down.map { |move| Board::Move.new(move.column, move.row, 1, move.word) }
    result = {}
    moves.each do |move|
      new_tiles = Scoring.placement(board, move)
      if new_tiles.size == 1 && move.direction == 1
        row, column = new_tiles.first
        next if Board.run_at(Scoring.apply(board, new_tiles), row, column, 0).word.size >= 2
      end
      result[new_tiles.sort] = move
    end
    result.values
  end
end

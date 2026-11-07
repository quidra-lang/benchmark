require_relative 'board'

module Scoring
  RACK_SIZE = 7
  BINGO_BONUS = 50
  module_function

  def squares(move)
    move.word.chars.each_with_index.map do |letter, offset|
      [move.row + move.direction * offset, move.column + (1 - move.direction) * offset, letter]
    end
  end

  def placement(board, move)
    squares(move).select { |row, column, _| board[row][column] == '.' }
  end

  def apply(board, new_tiles)
    result = board.map(&:dup)
    new_tiles.each { |row, column, letter| result[row][column] = letter }
    result
  end

  def cross_words(board, move)
    new_tiles = placement(board, move)
    after = apply(board, new_tiles)
    new_tiles.filter_map do |row, column, _|
      word = Board.run_at(after, row, column, 1 - move.direction)
      word if word.word.size >= 2
    end
  end

  def word_score(board, word, values)
    score, multiplier = 0, 1
    squares(word).each do |row, column, letter|
      value = /[A-Z]/.match?(letter) ? values[letter] : 0
      if board[row][column] == '.'
        premium = Board::PREMIUMS[row][column]
        value *= premium == '+' ? 2 : (premium == '^' ? 3 : 1)
        multiplier *= premium == '*' ? 2 : (premium == '#' ? 3 : 1)
      end
      score += value
    end
    score * multiplier
  end

  def score_move(board, move, values)
    words = [move, *cross_words(board, move)]
    scores = words.map { |word| word_score(board, word, values) }
    new_tiles = placement(board, move)
    [scores.reduce(0, :+) + (new_tiles.size == RACK_SIZE ? BINGO_BONUS : 0), new_tiles, words.zip(scores)]
  end
end

require 'set'

module Board
  SIZE = 15
  CENTER = [7, 7].freeze
  COLUMNS = 'ABCDEFGHIJKLMNO'
  Move = Data.define(:row, :column, :direction, :word)
  PREMIUMS = [
    '# . . + . . . # . . . + . . #',
    '. * . . . ^ . . . ^ . . . * .',
    '. . * . . . + . + . . . * . .',
    '+ . . * . . . + . . . * . . +',
    '. . . . * . . . . . * . . . .',
    '. ^ . . . ^ . . . ^ . . . ^ .',
    '. . + . . . + . + . . . + . .',
    '# . . + . . . * . . . + . . #',
    '. . + . . . + . + . . . + . .',
    '. ^ . . . ^ . . . ^ . . . ^ .',
    '. . . . * . . . . . * . . . .',
    '+ . . * . . . + . . . * . . +',
    '. . * . . . + . + . . . * . .',
    '. * . . . ^ . . . ^ . . . * .',
    '# . . + . . . # . . . + . . #'
  ].map(&:split).freeze
  module_function

  def inside?(row, column)
    row >= 0 && row < SIZE && column >= 0 && column < SIZE
  end

  def square_name(row, column)
    "#{COLUMNS[column]}#{row + 1}"
  end

  def position(move)
    move.direction == 0 ? "#{move.row + 1}#{COLUMNS[move.column]}" : "#{COLUMNS[move.column]}#{move.row + 1}"
  end

  def parse_position(text)
    if /\A([1-9]|1[0-5])[A-O]\z/.match?(text)
      [text[0...-1].to_i - 1, COLUMNS.index(text[-1]), 0]
    elsif /\A[A-O]([1-9]|1[0-5])\z/.match?(text)
      [text[1..].to_i - 1, COLUMNS.index(text[0]), 1]
    end
  end

  def transpose(board)
    board.transpose
  end

  def transpose_tiles(tiles)
    tiles.map { |row, column, letter| [column, row, letter] }
  end

  def tiles(board)
    board.each_with_index.flat_map do |values, row|
      values.each_with_index.filter_map { |letter, column| [row, column, letter] unless letter == '.' }
    end
  end

  def neighbors(row, column)
    [[row - 1, column], [row + 1, column], [row, column - 1], [row, column + 1]].select { |r, c| inside?(r, c) }
  end

  def run_at(board, row, column, direction)
    dr, dc = direction, 1 - direction
    while inside?(row - dr, column - dc) && board[row - dr][column - dc] != '.'
      row -= dr
      column -= dc
    end
    first_row, first_column, word = row, column, +''
    while inside?(row, column) && board[row][column] != '.'
      word << board[row][column]
      row += dr
      column += dc
    end
    Move.new(first_row, first_column, direction, word)
  end

  def words(board)
    result = []
    [0, 1].each do |direction|
      SIZE.times do |line|
        offset = 0
        while offset < SIZE
          row, column = direction == 0 ? [line, offset] : [offset, line]
          if board[row][column] == '.'
            offset += 1
          else
            move = run_at(board, row, column, direction)
            result << move if move.word.size >= 2
            offset += move.word.size
          end
        end
      end
    end
    result
  end

  def connected?(board)
    occupied = tiles(board).map { |row, column, _| [row, column] }.to_set
    return true if occupied.empty?
    pending = [occupied.first]
    seen = pending.to_set
    until pending.empty?
      neighbors(*pending.pop).each do |point|
        next unless occupied.include?(point) && !seen.include?(point)
        seen.add(point)
        pending << point
      end
    end
    seen == occupied
  end

  def display(board)
    ['   ' + COLUMNS.chars.join(' ')] + board.each_with_index.map do |values, row|
      format('%2d ', row + 1) + values.each_with_index.map { |letter, column| letter == '.' ? PREMIUMS[row][column] : letter }.join(' ')
    end
  end
end

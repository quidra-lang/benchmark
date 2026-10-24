# frozen_string_literal: true

module LinearModels
  def self.cholesky(matrix, right)
    count = right.length
    lower = Array.new(count) { Array.new(count, 0.0) }
    count.times do |row|
      (0..row).each do |column|
        total = 0.0
        column.times { |index| total += lower[row][index] * lower[column][index] }
        remainder = matrix[row][column] - total
        lower[row][column] = row == column ? Math.sqrt(remainder) : remainder / lower[column][column]
      end
    end
    intermediate = Array.new(count, 0.0)
    count.times do |row|
      total = 0.0
      row.times { |index| total += lower[row][index] * intermediate[index] }
      intermediate[row] = (right[row] - total) / lower[row][row]
    end
    solution = Array.new(count, 0.0)
    (count - 1).downto(0) do |row|
      total = 0.0
      (row + 1...count).each { |index| total += lower[index][row] * solution[index] }
      solution[row] = (intermediate[row] - total) / lower[row][row]
    end
    solution
  end

  def self.colley(count, matches)
    matrix = Array.new(count) { Array.new(count, 0) }
    differences = Array.new(count, 0)
    count.times { |index| matrix[index][index] = 2 }
    matches.each do |match|
      home = match.home
      away = match.away
      matrix[home][home] += 1
      matrix[away][away] += 1
      matrix[home][away] -= 1
      matrix[away][home] -= 1
      result = match.home_score <=> match.away_score
      differences[home] += result
      differences[away] -= result
    end
    right = differences.map { |difference| 1.0 + difference / 2.0 }
    cholesky(matrix, right)
  end

  def self.eliminate(matrix, right)
    count = right.length
    count.times do |column|
      pivot = column
      (column + 1...count).each do |row|
        pivot = row if matrix[row][column].abs > matrix[pivot][column].abs
      end
      matrix[column], matrix[pivot] = matrix[pivot], matrix[column]
      right[column], right[pivot] = right[pivot], right[column]
      (column + 1...count).each do |row|
        factor = matrix[row][column] / matrix[column][column]
        (column...count).each { |index| matrix[row][index] -= factor * matrix[column][index] }
        right[row] -= factor * right[column]
      end
    end
    solution = Array.new(count, 0.0)
    (count - 1).downto(0) do |row|
      total = 0.0
      (row + 1...count).each { |column| total += matrix[row][column] * solution[column] }
      solution[row] = (right[row] - total) / matrix[row][row]
    end
    solution
  end

  def self.massey(count, matches)
    size = count + 1
    matrix = Array.new(size) { Array.new(size, 0.0) }
    right = Array.new(size, 0.0)
    matches.each do |match|
      home = match.home
      away = match.away
      margin = match.home_score - match.away_score
      matrix[home][home] += 1
      matrix[away][away] += 1
      matrix[home][away] -= 1
      matrix[away][home] -= 1
      matrix[home][count] += 1
      matrix[count][home] += 1
      matrix[away][count] -= 1
      matrix[count][away] -= 1
      matrix[count][count] += 1
      right[home] += margin
      right[away] -= margin
      right[count] += margin
    end
    matrix[count - 1] = Array.new(size) { |column| column < count ? 1.0 : 0.0 }
    right[count - 1] = 0.0
    solution = eliminate(matrix, right)
    [solution.first(count), solution[count]]
  end
end

module Solver
  def self.cholesky(matrix, free)
    size = matrix.length
    lower = Array.new(size) { Array.new(size, 0.0) }
    size.times do |row|
      (0..row).each do |column|
        value = matrix[row][column]
        column.times { |index| value -= lower[row][index] * lower[column][index] }
        if column < row
          lower[row][column] = value / lower[column][column]
        else
          return [nil, free[row]] if value <= 0.000000001 * matrix[row][row]

          lower[row][row] = Math.sqrt(value)
        end
      end
    end
    [lower, nil]
  end

  def self.solve(lower, right)
    size = right.length
    intermediate, result = Array.new(size, 0.0), Array.new(size, 0.0)
    size.times do |row|
      value = right[row]
      row.times { |column| value -= lower[row][column] * intermediate[column] }
      intermediate[row] = value / lower[row][row]
    end
    (size - 1).downto(0) do |row|
      value = intermediate[row]
      ((row + 1)...size).each { |column| value -= lower[column][row] * result[column] }
      result[row] = value / lower[row][row]
    end
    result
  end
end

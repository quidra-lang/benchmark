module HarmonicFit
  PI = 3.141592653589793
  module_function

  def angle(speed, time)
    degrees = speed * time
    reduced = degrees - 360 * (degrees / 360).floor
    reduced * PI / 180
  end

  def regressors(constituents, time)
    [1.0] + constituents.flat_map do |item|
      theta = angle(item[:speed], time)
      [Math.cos(theta), Math.sin(theta)]
    end
  end

  def normal_equations(rows, constituents)
    size = 2 * constituents.length + 1
    matrix = Array.new(size) { Array.new(size, 0.0) }
    rhs = Array.new(size, 0.0)
    rows.each do |row|
      x = regressors(constituents, row[:time])
      size.times do |i|
        size.times { |j| matrix[i][j] += x[i] * x[j] }
        rhs[i] += x[i] * row[:value]
      end
    end
    [matrix, rhs]
  end

  def solve(matrix, rhs)
    size = rhs.length
    augmented = matrix.each_with_index.map { |row, i| row + [rhs[i]] + Array.new(size) { |j| i == j ? 1.0 : 0.0 } }
    size.times do |column|
      pivot = column
      (column + 1...size).each { |row| pivot = row if augmented[row][column].abs > augmented[pivot][column].abs }
      augmented[pivot], augmented[column] = augmented[column], augmented[pivot] if pivot != column
      (column + 1...size).each do |row|
        factor = augmented[row][column] / augmented[column][column]
        (column..2 * size).each { |c| augmented[row][c] -= factor * augmented[column][c] }
      end
    end
    coefficients = nil
    inverse = Array.new(size) { Array.new(size) }
    (size..2 * size).each do |column|
      solution = Array.new(size)
      (size - 1).downto(0) do |row|
        value = augmented[row][column]
        (row + 1...size).each { |j| value -= augmented[row][j] * solution[j] }
        solution[row] = value / augmented[row][row]
      end
      if column == size
        coefficients = solution
      else
        size.times { |row| inverse[row][column - size - 1] = solution[row] }
      end
    end
    [coefficients, inverse]
  end

  def fit(rows, constituents)
    coefficients, inverse = solve(*normal_equations(rows, constituents))
    fitted = constituents.each_with_index.map do |item, index|
      a, b = coefficients[2 * index + 1, 2]
      phase = Math.atan2(b, a) * 180 / PI
      phase += 360 if phase < 0
      item.merge(a: a, b: b, amplitude: Math.sqrt(a * a + b * b), phase: phase)
    end
    {mean: coefficients[0], unknowns: coefficients.length, inverse: inverse, constituents: fitted}
  end
end

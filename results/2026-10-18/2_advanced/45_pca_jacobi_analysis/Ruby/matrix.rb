module MatrixOps
  module_function

  # Enumerable#sum uses compensation for floats; the specification requires this order.
  def total(values)
    result = 0.0
    values.each { |value| result += value }
    result
  end

  def identity(size)
    Array.new(size) { |i| Array.new(size) { |j| i == j ? 1.0 : 0.0 } }
  end

  def copy(matrix)
    matrix.map(&:dup)
  end

  def column(matrix, index)
    matrix.map { |row| row[index] }
  end

  def dot(first, second)
    result = 0.0
    first.each_index { |j| result += first[j] * second[j] }
    result
  end

  def multiply(matrix, vector)
    matrix.map { |row| dot(row, vector) }
  end

  def length(vector)
    Math.sqrt(dot(vector, vector))
  end

  def normalize(vector)
    norm = length(vector)
    vector.map { |value| value / norm }
  end

  def orient(vector)
    largest = vector.each_index.max_by { |j| [vector[j].abs, -j] }
    vector[largest].negative? ? vector.map { |value| -value } : vector
  end

  def max_difference(first, second)
    first.each_index.map { |j| (first[j] - second[j]).abs }.max
  end

  def deflate(matrix, value, vector)
    matrix.each_with_index do |row, i|
      row.each_index { |j| row[j] -= value * vector[i] * vector[j] }
    end
  end

  def gauss_jordan(matrix)
    size = matrix.length
    unit = identity(size)
    augmented = matrix.each_with_index.map { |row, i| row.dup + unit[i] }
    determinant = 1.0
    size.times do |k|
      pivot = augmented[k][k]
      determinant *= pivot
      augmented[k].map! { |value| value / pivot }
      size.times do |i|
        next if i == k

        gamma = augmented[i][k]
        (2 * size).times { |h| augmented[i][h] -= gamma * augmented[k][h] }
      end
    end
    [augmented.map { |row| row.drop(size) }, determinant]
  end
end

module Mat
  def self.total(values)
    values.reduce(0.0) { |sum, value| sum + value }
  end

  def self.zeros(rows, columns = rows)
    Array.new(rows) { Array.new(columns, 0.0) }
  end

  def self.diagonal(values)
    result = zeros(values.length)
    values.each_with_index { |value, i| result[i][i] = value }
    result
  end

  def self.identity(size)
    diagonal(Array.new(size, 1.0))
  end

  def self.transpose(a)
    a.transpose
  end

  def self.add(a, b)
    a.each_index.map { |i| a[i].each_index.map { |j| a[i][j] + b[i][j] } }
  end

  def self.subtract(a, b)
    a.each_index.map { |i| a[i].each_index.map { |j| a[i][j] - b[i][j] } }
  end

  def self.vector_add(a, b)
    a.each_index.map { |i| a[i] + b[i] }
  end

  def self.vector_subtract(a, b)
    a.each_index.map { |i| a[i] - b[i] }
  end

  def self.product(a, b)
    columns = transpose(b)
    a.map { |row| columns.map { |column| total(row.each_index.map { |i| row[i] * column[i] }) } }
  end

  def self.matrix_vector(a, vector)
    a.map { |row| total(row.each_index.map { |i| row[i] * vector[i] }) }
  end

  def self.inverse(a)
    size = a.length
    unit = identity(size)
    augmented = a.each_with_index.map { |row, i| row + unit[i] }
    size.times do |c|
      pivot = augmented[c][c]
      (2 * size).times { |j| augmented[c][j] /= pivot }
      size.times do |i|
        next if i == c
        factor = augmented[i][c]
        (2 * size).times { |j| augmented[i][j] -= factor * augmented[c][j] }
      end
    end
    augmented.map { |row| row.drop(size) }
  end

  def self.determinant2(a)
    a[0][0] * a[1][1] - a[0][1] * a[1][0]
  end

  def self.quadratic2(vector, a)
    x, y = vector
    x * (a[0][0] * x + a[0][1] * y) + y * (a[1][0] * x + a[1][1] * y)
  end
end

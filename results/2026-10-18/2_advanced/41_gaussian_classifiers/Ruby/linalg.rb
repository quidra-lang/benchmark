module Linalg
  extend self

  # Float sums must use ordinary additions in sequence order.
  def total(values)
    values.reduce(0.0) { |sum, value| sum + value }
  end

  def dot(left, right)
    total(left.zip(right).map { |a, b| a * b })
  end

  def zeros(size)
    Array.new(size) { Array.new(size, 0.0) }
  end

  def cholesky(matrix)
    size = matrix.length
    lower = zeros(size)
    size.times do |i|
      (0..i).each do |j|
        subtotal = total((0...j).map { |k| lower[i][k] * lower[j][k] })
        remainder = matrix[i][j] - subtotal
        lower[i][j] = i == j ? Math.sqrt(remainder) : remainder / lower[j][j]
      end
    end
    lower
  end

  def forward(lower, right)
    result = Array.new(lower.length, 0.0)
    lower.length.times do |i|
      subtotal = total((0...i).map { |k| lower[i][k] * result[k] })
      result[i] = (right[i] - subtotal) / lower[i][i]
    end
    result
  end

  def backward(lower, right)
    size = lower.length
    result = Array.new(size, 0.0)
    (size - 1).downto(0) do |i|
      subtotal = total(((i + 1)...size).map { |k| lower[k][i] * result[k] })
      result[i] = (right[i] - subtotal) / lower[i][i]
    end
    result
  end

  def log_determinant(lower)
    2 * total(lower.each_index.map { |i| Math.log(lower[i][i]) })
  end

  def quadratic_form(lower, difference)
    transformed = forward(lower, difference)
    dot(transformed, transformed)
  end

  def jacobi(matrix)
    size = matrix.length
    current = matrix.map(&:dup)
    vectors = zeros(size)
    size.times { |i| vectors[i][i] = 1.0 }
    sweeps = 0
    loop do
      off_squared = 0.0
      (0...(size - 1)).each do |a|
        ((a + 1)...size).each { |b| off_squared += current[a][b] * current[a][b] }
      end
      break if Math.sqrt(off_squared) < 1e-12 || sweeps == 50

      (0...(size - 1)).each do |a|
        ((a + 1)...size).each do |b|
          next if current[a][b].zero?

          theta = (current[b][b] - current[a][a]) / (2 * current[a][b])
          sign = theta >= 0 ? 1 : -1
          tangent = sign / (theta.abs + Math.sqrt(theta * theta + 1))
          cosine = 1 / Math.sqrt(tangent * tangent + 1)
          sine = tangent * cosine
          size.times do |k|
            next if k == a || k == b

            x, y = current[k][a], current[k][b]
            current[k][a] = current[a][k] = cosine * x - sine * y
            current[k][b] = current[b][k] = sine * x + cosine * y
          end
          value = current[a][b]
          current[a][a] = current[a][a] - tangent * value
          current[b][b] = current[b][b] + tangent * value
          current[a][b] = current[b][a] = 0.0
          size.times do |k|
            x, y = vectors[k][a], vectors[k][b]
            vectors[k][a] = cosine * x - sine * y
            vectors[k][b] = sine * x + cosine * y
          end
        end
      end
      sweeps += 1
    end
    [current.each_index.map { |i| current[i][i] }, vectors, sweeps]
  end
end

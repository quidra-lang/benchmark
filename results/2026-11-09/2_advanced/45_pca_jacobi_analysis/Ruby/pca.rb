require_relative 'matrix'

module PCA
  module_function

  def means(rows)
    Array.new(rows[0].length) { |j| MatrixOps.total(rows.map { |row| row[j] }) / rows.length }
  end

  def covariance(rows, means)
    size = means.length
    deviations = rows.map { |row| Array.new(size) { |j| row[j] - means[j] } }
    matrix = Array.new(size) { Array.new(size, 0.0) }
    size.times do |j|
      (j...size).each do |k|
        products = MatrixOps.total(deviations.map { |row| row[j] * row[k] })
        matrix[j][k] = matrix[k][j] = products / (rows.length - 1)
      end
    end
    matrix
  end

  def standard_deviations(covariance)
    Array.new(covariance.length) { |j| Math.sqrt(covariance[j][j]) }
  end

  def correlation(covariance, deviations)
    Array.new(covariance.length) do |j|
      Array.new(covariance.length) do |k|
        j == k ? 1.0 : covariance[j][k] / (deviations[j] * deviations[k])
      end
    end
  end

  def standardize(values, means, scales)
    values.each_with_index.map { |value, j| value.nil? ? 0.0 : (value - means[j]) / scales[j] }
  end

  def scores(z, vectors)
    vectors.map { |vector| MatrixOps.dot(z, vector) }
  end

  def residuals(z, scores, vectors, count)
    z.each_index.map do |j|
      fitted = 0.0
      count.times { |k| fitted += scores[k] * vectors[k][j] }
      z[j] - fitted
    end
  end

  def hotelling_t2(scores, eigenvalues, count)
    total = 0.0
    count.times { |k| total += (scores[k] * scores[k]) / eigenvalues[k] }
    total
  end
end

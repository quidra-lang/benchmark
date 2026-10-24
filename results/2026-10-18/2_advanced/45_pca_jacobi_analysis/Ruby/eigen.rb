require_relative 'matrix'

module Eigen
  MAX_SWEEPS = 100
  STOP_FACTOR = 1e-22
  COUNT_FACTOR = 1e-16
  POWER_ITERATIONS = 1000
  AGREEMENT_TOLERANCE = 0.000001
  System = Data.define(:values, :vectors, :sweeps)
  PowerComponent = Data.define(:value, :vector, :agreement)

  module_function

  def off_diagonal(matrix)
    total = 0.0
    (matrix.length - 1).times do |p|
      ((p + 1)...matrix.length).each { |q| total += matrix[p][q] * matrix[p][q] }
    end
    total
  end

  def rotate(a, v, p, q)
    return if a[p][q].zero?

    theta = (a[q][q] - a[p][p]) / (2 * a[p][q])
    t = 1.0 / (theta.abs + Math.sqrt(theta * theta + 1))
    t = -t if theta.negative?
    c = 1.0 / Math.sqrt(t * t + 1)
    s = t * c
    a.length.times do |r|
      next if r == p || r == q

      arp, arq = a[r][p], a[r][q]
      a[r][p] = a[p][r] = c * arp - s * arq
      a[r][q] = a[q][r] = s * arp + c * arq
    end
    apq = a[p][q]
    a[p][p] -= t * apq
    a[q][q] += t * apq
    a[p][q] = a[q][p] = 0.0
    v.each do |row|
      first, second = row[p], row[q]
      row[p] = c * first - s * second
      row[q] = s * first + c * second
    end
  end

  def sweep(a, v)
    (a.length - 1).times do |p|
      ((p + 1)...a.length).each { |q| rotate(a, v, p, q) }
    end
  end

  def jacobi(matrix)
    a = MatrixOps.copy(matrix)
    v = MatrixOps.identity(matrix.length)
    initial = off_diagonal(a)
    sweeps = 0
    if initial.positive?
      1.upto(MAX_SWEEPS) do |number|
        sweep(a, v)
        remaining = off_diagonal(a)
        sweeps = number if sweeps.zero? && remaining < COUNT_FACTOR * initial
        break if remaining < STOP_FACTOR * initial
      end
    end
    order = a.each_index.sort_by { |k| [-a[k][k], k] }
    values = order.map { |k| a[k][k] }
    vectors = order.map { |k| MatrixOps.orient(MatrixOps.normalize(MatrixOps.column(v, k))) }
    System.new(values, vectors, sweeps)
  end

  def power_iteration(matrix, references)
    b = MatrixOps.copy(matrix)
    references.map do |reference|
      opposite = reference.map { |value| -value }
      x = Array.new(b.length, 1.0)
      agreement = nil
      1.upto(POWER_ITERATIONS) do |step|
        x = MatrixOps.normalize(MatrixOps.multiply(b, x))
        difference = [MatrixOps.max_difference(x, reference),
                      MatrixOps.max_difference(x, opposite)].min
        agreement = step if agreement.nil? && difference < AGREEMENT_TOLERANCE
      end
      value = MatrixOps.dot(x, MatrixOps.multiply(b, x))
      vector = MatrixOps.orient(MatrixOps.normalize(x))
      MatrixOps.deflate(b, value, vector)
      PowerComponent.new(value, vector, agreement)
    end
  end
end

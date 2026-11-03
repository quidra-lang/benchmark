module Numerics
  Z95 = 1.959963984540054
  LANCZOS = [76.18009172947146, -86.50532032941677, 24.01409824083091,
             -1.231739572450155, 0.001208650973866179, -0.000005395239384953].freeze
  module_function

  # Float sums must use the specified order, without compensated summation.
  def total(values)
    result = 0.0
    values.each { |value| result += value }
    result
  end

  def solve(matrix, vector)
    a = matrix.map(&:dup)
    b = vector.dup
    size = b.length
    size.times do |k|
      (k + 1...size).each do |i|
        factor = a[i][k] / a[k][k]
        (k...size).each { |j| a[i][j] -= factor * a[k][j] }
        b[i] -= factor * b[k]
      end
    end
    solution = Array.new(size, 0.0)
    (size - 1).downto(0) do |i|
      value = b[i]
      (i + 1...size).each { |j| value -= a[i][j] * solution[j] }
      solution[i] = value / a[i][i]
    end
    solution
  end

  def inverse(matrix)
    size = matrix.length
    result = Array.new(size) { Array.new(size, 0.0) }
    size.times do |column|
      unit = Array.new(size, 0.0)
      unit[column] = 1.0
      solution = solve(matrix, unit)
      size.times { |row| result[row][column] = solution[row] }
    end
    result
  end

  def log_gamma(a)
    xi = a + 5.5
    xi -= (a + 0.5) * Math.log(xi)
    sigma = 1.000000000190015
    y = a
    LANCZOS.each do |coefficient|
      y += 1.0
      sigma += coefficient / y
    end
    -xi + Math.log(2.5066282746310005 * sigma / a)
  end

  def gamma_q(a, x)
    return 1.0 if x.zero?

    prefactor = Math.exp(-x + a * Math.log(x) - log_gamma(a))
    if x < a + 1.0
      alpha = a
      term = 1.0 / a
      sigma = term
      1000.times do
        alpha += 1.0
        term *= x / alpha
        sigma += term
        break if term.abs < sigma.abs * 1e-15
      end
      return 1.0 - sigma * prefactor
    end

    epsilon = 1e-300
    b = x + 1.0 - a
    c = 1.0 / epsilon
    d = 1.0 / b
    h = d
    1.upto(1000) do |i|
      an = -i * (i - a)
      b += 2.0
      d = an * d + b
      d = epsilon if d.abs < epsilon
      c = b + an / c
      c = epsilon if c.abs < epsilon
      d = 1.0 / d
      delta = d * c
      h *= delta
      break if (delta - 1.0).abs < 1e-15
    end
    prefactor * h
  end

  def chi_square_p(statistic, degrees)
    gamma_q(degrees / 2.0, statistic / 2.0)
  end
end

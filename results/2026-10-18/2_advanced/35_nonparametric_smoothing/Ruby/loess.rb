require_relative 'selection'

class LoessFit
  attr_reader :fitted, :leverage, :edf, :rho, :records

  def self.median(values)
    ordered = values.sort
    middle = ordered.length / 2
    ordered.length.odd? ? ordered[middle] : (ordered[middle - 1] + ordered[middle]) / 2.0
  end

  def self.cholesky(matrix)
    size = matrix.length
    lower = Array.new(size) { Array.new(size, 0.0) }
    size.times do |row|
      (0..row).each do |column|
        sigma = matrix[row][column]
        column.times { |k| sigma -= lower[row][k] * lower[column][k] }
        lower[row][column] = row == column ? Math.sqrt(sigma) : sigma / lower[column][column]
      end
    end
    lower
  end

  def self.solve(lower, right)
    size = right.length
    intermediate = Array.new(size, 0.0)
    size.times do |row|
      value = right[row]
      row.times { |k| value -= lower[row][k] * intermediate[k] }
      intermediate[row] = value / lower[row][row]
    end
    solution = Array.new(size, 0.0)
    (size - 1).downto(0) do |row|
      value = intermediate[row]
      ((row + 1)...size).each { |k| value -= lower[k][row] * solution[k] }
      solution[row] = value / lower[row][row]
    end
    solution
  end

  def initialize(positions, values, span, degree, iterations, diagnostics: true)
    @positions, @y, @span, @degree = positions, values, span, degree
    @x = positions.map { |position| position / 100.0 }
    @rho = Array.new(positions.length, 1.0)
    @records, @cache = [], {}
    @fitted = @leverage = @edf = nil
    return unless diagnostics

    fits = positions.map { |position| local_fit(position) }
    1.upto(iterations) do |iteration|
      residuals = values.each_index.map { |i| values[i] - fits[i][0] }
      scale = self.class.median(residuals.map(&:abs))
      @rho = residuals.map do |residual|
        u = residual / (6 * scale)
        nu = 1 - u * u
        u.abs < 1 ? nu * nu : 0.0
      end
      updated = positions.map { |position| local_fit(position) }
      change = fits.each_index.map { |i| (updated[i][0] - fits[i][0]).abs }.max
      @records << [iteration, scale, @rho.count(0.0), change]
      fits = updated
    end
    @cache = positions.zip(fits).to_h
    @fitted = fits.map(&:first)
    @leverage = fits.each_index.map { |i| @rho[i] * fits[i][1] }
    @edf = Selection.sum(@leverage)
  end

  def local_fit(position)
    count = @positions.length
    q = @span * count / 100
    neighborhood = @positions.each_index.sort_by { |i| [(@positions[i] - position).abs, i] }.first(q)
    distance = neighborhood.map { |i| (@positions[i] - position).abs }.max
    size = @degree + 1
    matrix = Array.new(size) { Array.new(size, 0.0) }
    right = Array.new(size, 0.0)
    x0 = position / 100.0
    rows = neighborhood.sort.map do |i|
      a = (@positions[i] - position).abs.to_f / distance.to_f
      s = 1 - a * a * a
      weight = s * s * s * @rho[i]
      delta = @x[i] - x0
      basis = @degree == 1 ? [1.0, delta] : [1.0, delta, delta * delta]
      size.times do |row|
        right[row] += weight * basis[row] * @y[i]
        size.times { |column| matrix[row][column] += weight * basis[row] * basis[column] }
      end
      [i, weight, basis]
    end
    lower = self.class.cholesky(matrix)
    beta = self.class.solve(lower, right)
    zeta = self.class.solve(lower, [1.0] + Array.new(@degree, 0.0))
    weights = Array.new(count, 0.0)
    rows.each do |i, weight, basis|
      weights[i] = weight * Selection.sum(0...size) { |k| zeta[k] * basis[k] }
    end
    [beta[0], zeta[0], weights]
  end

  def evaluate(position)
    @cache[position] ||= local_fit(position)
  end

  def estimate(position)
    evaluate(position)[0]
  end

  def weights(position)
    evaluate(position)[2]
  end
end

module Steady
  def self.g_value(system, field, p)
    terms = system[:faces][p].filter_map do |face|
      if face[:neighbor]
        face[:g] * field[face[:neighbor]]
      elsif face[:theta]
        face[:g] * face[:theta]
      end
    end
    Transient.sum(terms) + system[:source_all][p]
  end

  def self.iterate(system, initial, tolerance, maximum, method, omega = 1.0)
    field = Array.new(system[:mesh].count, initial)
    changes = []
    maximum.times do
      previous = field.dup
      if method == 'jacobi'
        field = field.each_index.map { |p| g_value(system, previous, p) / system[:diagonal][p] }
      else
        field.each_index do |p|
          value = g_value(system, field, p) / system[:diagonal][p]
          field[p] = method == 'gauss_seidel' ? value : field[p] + omega * (value - field[p])
        end
      end
      changes << field.zip(previous).map { |a, b| (a - b).abs }.max
      break if changes[-1] < tolerance
    end
    { method: method, field: field, changes: changes, iterations: changes.size,
      converged: changes[-1] < tolerance, omega: omega }
  end

  def self.band_solve(system, right_hand_sides)
    count, width = system[:mesh].count, system[:mesh].width
    matrix = Array.new(count) { Array.new(count, 0.0) }
    system[:faces].each_with_index do |faces, p|
      matrix[p][p] = system[:diagonal][p]
      faces.each { |face| matrix[p][face[:neighbor]] = -face[:g] if face[:neighbor] }
    end
    vectors = right_hand_sides.map(&:dup)
    count.times do |k|
      stop = [count - 1, k + width].min
      (k + 1..stop).each do |i|
        factor = matrix[i][k] / matrix[k][k]
        matrix[i][k] = 0.0
        (k + 1..stop).each { |j| matrix[i][j] -= factor * matrix[k][j] }
        vectors.each { |values| values[i] -= factor * values[k] }
      end
    end
    vectors.map do |values|
      field = Array.new(count, 0.0)
      (count - 1).downto(0) do |i|
        value = values[i]
        (i + 1..[count - 1, i + width].min).each { |j| value -= matrix[i][j] * field[j] }
        field[i] = value / matrix[i][i]
      end
      field
    end
  end

  def self.residual(system, field, rhs)
    field.each_index.map do |p|
      value = rhs[p]
      system[:faces][p].each { |face| value += face[:g] * field[face[:neighbor]] if face[:neighbor] }
      (value - system[:diagonal][p] * field[p]).abs
    end.max
  end
end

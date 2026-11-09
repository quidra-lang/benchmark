module Transient
  def self.sum(values)
    values.reduce { |total, value| total + value } || 0.0
  end

  def self.flow(system, field, point, directions)
    sum(directions.filter_map do |direction|
      face = system[:faces][point][direction]
      if face[:neighbor]
        face[:g] * (field[face[:neighbor]] - field[point])
      elsif face[:theta]
        face[:g] * (face[:theta] - field[point])
      end
    end)
  end

  def self.thomas(lower, diagonal, upper, rhs)
    nu = [upper[0] / diagonal[0]]
    phi = [rhs[0] / diagonal[0]]
    (1...diagonal.size).each do |i|
      pivot = diagonal[i] - lower[i] * nu[i - 1]
      nu << upper[i] / pivot
      phi << (rhs[i] - lower[i] * phi[i - 1]) / pivot
    end
    result = Array.new(diagonal.size, 0.0)
    result[-1] = phi[-1]
    (diagonal.size - 2).downto(0) { |i| result[i] = phi[i] - nu[i] * result[i + 1] }
    result
  end

  def self.sweep(system, tau, rhs, horizontal)
    mesh = system[:mesh]
    lines, length = horizontal ? [mesh.height, mesh.width] : [mesh.width, mesh.height]
    first, second = horizontal ? [0, 1] : [2, 3]
    field = Array.new(mesh.count, 0.0)
    lines.times do |line|
      cells = Array.new(length) { |i| horizontal ? mesh.cell(line, i) : mesh.cell(i, line) }
      lower, diagonal, upper, values = [], [], [], []
      cells.each do |p|
        a, b = system[:faces][p].values_at(first, second)
        lower << (a[:neighbor] ? -a[:g] : 0.0)
        diagonal << system[:capacity][p] / tau + a[:g] + b[:g]
        upper << (b[:neighbor] ? -b[:g] : 0.0)
        value = rhs[p]
        value += a[:g] * a[:theta] if a[:theta]
        value += b[:g] * b[:theta] if b[:theta]
        values << value
      end
      solved = thomas(lower, diagonal, upper, values)
      cells.each_with_index { |p, i| field[p] = solved[i] }
    end
    field
  end

  def self.advance(method, system, field, source, dt)
    count = system[:mesh].count
    capacity = system[:capacity]
    if method == 'ftcs'
      return [Array.new(count) { |p| field[p] + dt * (flow(system, field, p, [0, 1, 2, 3]) + source[p]) / capacity[p] }, nil]
    end
    tau = method == 'backward_euler' ? dt : dt / 2
    vertical = Array.new(count) { |p| flow(system, field, p, [2, 3]) }
    rhs = Array.new(count) { |p| capacity[p] / tau * field[p] + vertical[p] + source[p] }
    intermediate = sweep(system, tau, rhs, true)
    rhs = Array.new(count) do |p|
      if method == 'backward_euler'
        capacity[p] / dt * intermediate[p] - vertical[p]
      else
        capacity[p] / tau * intermediate[p] + flow(system, intermediate, p, [0, 1]) + source[p]
      end
    end
    [sweep(system, tau, rhs, false), intermediate]
  end
end

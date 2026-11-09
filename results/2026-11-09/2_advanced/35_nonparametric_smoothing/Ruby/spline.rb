require_relative 'selection'

class SplineFit
  attr_reader :fitted, :leverage, :edf

  def initialize(positions, values, penalty, diagnostics: true)
    @positions, @penalty = positions, penalty
    @x = positions.map { |position| position / 100.0 }
    @h = @x.each_cons(2).map { |left, right| right - left }
    decompose
    @fit = fit_values(values)
    @fitted = @fit.first
    @basis = @leverage = @edf = nil
    prepare_basis if diagnostics
  end

  def decompose
    size = @positions.length - 2
    a = Array.new(size) { |i| 1.0 / @h[i] }
    c = Array.new(size) { |i| 1.0 / @h[i + 1] }
    b = Array.new(size) { |i| -(a[i] + c[i]) }
    diagonal = Array.new(size) do |i|
      (@h[i] + @h[i + 1]) / 3 + @penalty * (a[i] * a[i] + b[i] * b[i] + c[i] * c[i])
    end
    first = Array.new(size - 1) { |i| @h[i + 1] / 6 + @penalty * c[i] * (b[i] + b[i + 1]) }
    second = Array.new([size - 2, 0].max) { |i| @penalty * c[i] * c[i + 1] }
    @d, @l1, @l2 = Array.new(3) { Array.new(size, 0.0) }
    size.times do |i|
      @l2[i] = second[i - 2] / @d[i - 2] if i >= 2
      if i >= 1
        correction = i >= 2 ? @l2[i] * @d[i - 2] * @l1[i - 1] : 0.0
        @l1[i] = (first[i - 1] - correction) / @d[i - 1]
      end
      value = diagonal[i]
      value -= @l1[i] * @l1[i] * @d[i - 1] if i >= 1
      value -= @l2[i] * @l2[i] * @d[i - 2] if i >= 2
      @d[i] = value
    end
  end

  def fit_values(values)
    count = values.length
    size = count - 2
    z = Array.new(size, 0.0)
    size.times do |i|
      value = (values[i + 2] - values[i + 1]) / @h[i + 1] - (values[i + 1] - values[i]) / @h[i]
      value -= @l1[i] * z[i - 1] if i >= 1
      value -= @l2[i] * z[i - 2] if i >= 2
      z[i] = value
    end
    gamma = Array.new(count, 0.0)
    (size - 1).downto(0) do |i|
      value = z[i] / @d[i]
      value -= @l1[i + 1] * gamma[i + 2] if i + 1 < size
      value -= @l2[i + 2] * gamma[i + 3] if i + 2 < size
      gamma[i + 1] = value
    end
    omega = [(gamma[1] - gamma[0]) / @h[0]]
    (1...(count - 1)).each do |i|
      omega << (gamma[i + 1] - gamma[i]) / @h[i] - (gamma[i] - gamma[i - 1]) / @h[i - 1]
    end
    omega << (0 - (gamma[-1] - gamma[-2]) / @h[-1])
    fitted = values.each_index.map { |i| values[i] - @penalty * omega[i] }
    [fitted, gamma]
  end

  def evaluate_fit(fit, position)
    fitted, gamma = fit
    x0 = position / 100.0
    index = @positions.bsearch_index { |x| x >= position } || @positions.length
    return fitted[index] if index < @positions.length && @positions[index] == position

    if index.zero?
      slope = (fitted[1] - fitted[0]) / @h[0] - @h[0] * gamma[1] / 6
      return fitted[0] - (@x[0] - x0) * slope
    end
    if index == @positions.length
      slope = (fitted[-1] - fitted[-2]) / @h[-1] + @h[-1] * gamma[-2] / 6
      return fitted[-1] + (x0 - @x[-1]) * slope
    end
    i = index - 1
    left = x0 - @x[i]
    right = @x[i + 1] - x0
    (left * fitted[i + 1] + right * fitted[i]) / @h[i] -
      left * right * ((1 + left / @h[i]) * gamma[i + 1] + (1 + right / @h[i]) * gamma[i]) / 6
  end

  def prepare_basis
    return if @basis

    count = @positions.length
    @basis = Array.new(count) do |i|
      unit = Array.new(count, 0.0)
      unit[i] = 1.0
      fit_values(unit)
    end
    @leverage = @basis.each_index.map { |i| @basis[i][0][i] }
    @edf = Selection.sum(@leverage)
  end

  def estimate(position)
    evaluate_fit(@fit, position)
  end

  def weights(position)
    prepare_basis
    @basis.map { |fit| evaluate_fit(fit, position) }
  end
end

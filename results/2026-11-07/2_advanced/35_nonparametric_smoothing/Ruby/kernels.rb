require_relative 'selection'

class KernelFit
  KAPPA = { 'epanechnikov' => 0.75, 'biweight' => 0.9375, 'triweight' => 1.09375 }.freeze
  attr_reader :fitted, :leverage, :edf

  def initialize(positions, values, bandwidth, kernel, local_linear, diagnostics: true)
    @positions, @y = positions, values
    @x = positions.map { |position| position / 100.0 }
    @bandwidth, @kernel, @local_linear = bandwidth, kernel, local_linear
    @cache = {}
    @fitted = @leverage = @edf = nil
    return unless diagnostics

    pairs = positions.map { |position| evaluate(position) }
    return if pairs.any? { |value, _weights| value.nil? }

    @fitted = pairs.map(&:first)
    @leverage = pairs.each_with_index.map { |(_value, weights), i| weights[i] }
    @edf = Selection.sum(@leverage)
  end

  def evaluate(position)
    return @cache[position] if @cache.key?(position)

    used = @positions.each_index.select { |i| (@positions[i] - position).abs < @bandwidth }
    return @cache[position] = [nil, nil] if used.length < (@local_linear ? 2 : 1)

    x0 = position / 100.0
    h = @bandwidth / 100.0
    differences = used.map { |i| @x[i] - x0 }
    kernels = differences.map do |delta|
      u = delta / h
      t = 1 - u * u
      weight = KAPPA.fetch(@kernel) * t
      weight *= t unless @kernel == 'epanechnikov'
      weight *= t if @kernel == 'triweight'
      weight
    end
    indices = used.each_index
    s0 = Selection.sum(kernels)
    t0 = Selection.sum(indices) { |j| kernels[j] * @y[used[j]] }
    weights = Array.new(@positions.length, 0.0)
    if @local_linear
      s1 = Selection.sum(indices) { |j| kernels[j] * differences[j] }
      s2 = Selection.sum(indices) { |j| kernels[j] * differences[j] * differences[j] }
      t1 = Selection.sum(indices) { |j| kernels[j] * differences[j] * @y[used[j]] }
      q = s0 * s2 - s1 * s1
      estimate = (s2 * t0 - s1 * t1) / q
      used.each_with_index { |i, j| weights[i] = kernels[j] * (s2 - s1 * differences[j]) / q }
    else
      estimate = t0 / s0
      used.each_with_index { |i, j| weights[i] = kernels[j] / s0 }
    end
    @cache[position] = [estimate, weights]
  end

  def estimate(position)
    evaluate(position).first
  end

  def weights(position)
    evaluate(position).last
  end
end

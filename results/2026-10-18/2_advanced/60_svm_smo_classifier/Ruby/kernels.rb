require_relative 'evaluation'

class KernelDefinition
  include Evaluation
  attr_reader :name, :kind

  def initialize(name, kind, *arguments)
    @name, @kind = name, kind
    if kind == 'poly'
      @degree, @gamma, @coef0 = arguments[0].to_i, arguments[1].to_f, arguments[2].to_f
    elsif kind == 'rbf'
      @gamma = arguments[0].to_f
    end
  end

  def value(a, b)
    if @kind == 'rbf'
      e1, e2 = a[0] - b[0], a[1] - b[1]
      return Math.exp(-@gamma * (e1 * e1 + e2 * e2))
    end
    dot = a[0] * b[0] + a[1] * b[1]
    return dot if @kind == 'linear'
    factor = @gamma * dot + @coef0
    result = 1.0
    @degree.times { result *= factor }
    result
  end

  def description
    return 'linear' if @kind == 'linear'
    return "rbf gamma #{fixed(@gamma)}" if @kind == 'rbf'
    "poly degree #{@degree} gamma #{fixed(@gamma)} coef0 #{fixed(@coef0)}"
  end

  def matrix(points) = points.map { |a| points.map { |b| value(a, b) } }
end

def submatrix(matrix, indices) = indices.map { |i| indices.map { |j| matrix[i][j] } }

require_relative 'smo'
require_relative 'kernels'

PAIRS = [[1, 2], [1, 3], [2, 3]].freeze
Classification = Data.define(:ovr_values, :ovo_values, :ovr, :ovo, :votes, :tied)

class MulticlassModels
  attr_reader :kernel, :c, :ovr_models, :ovo_models

  def initialize(examples, kernel, c, settings)
    @kernel, @c = kernel, c
    points, classes = examples.map(&:point), examples.map(&:class_number)
    matrix = kernel.matrix(points)
    @ovr_models = (1..3).map { |k| train(points, classes.map { |v| v == k ? 1 : -1 }, kernel, matrix, c, settings) }
    @ovo_models = PAIRS.map do |a, b|
      indices = classes.each_index.select { |i| classes[i] == a || classes[i] == b }
      train(indices.map { |i| points[i] }, indices.map { |i| classes[i] == a ? 1 : -1 }, kernel, submatrix(matrix, indices), c, settings)
    end
  end

  def classify(point)
    rest = @ovr_models.map { |m| m.decision(point) }
    ovr = (0...3).max_by { |i| [rest[i], -i] } + 1
    votes, scores = [0, 0, 0], [0.0, 0.0, 0.0]
    pair = @ovo_models.each_with_index.map do |model, i|
      a, b = PAIRS[i]
      h = model.decision(point)
      votes[(h > 0 ? a : b) - 1] += 1
      scores[a - 1] += h
      scores[b - 1] -= h
      h
    end
    candidates = (0...3).select { |i| votes[i] == votes.max }
    ovo = candidates.max_by { |i| [scores[i], -i] } + 1
    Classification.new(rest, pair, ovr, ovo, votes, candidates.size > 1)
  end
end

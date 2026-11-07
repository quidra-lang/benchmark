require_relative 'linalg'

module GaussianModels
  extend self

  MODEL_NAMES = %w[NB LDA QDA].freeze
  Prediction = Data.define(:predicted, :posterior, :log_posterior, :confidence, :decision)

  def argmax(values)
    values.each_index.max_by { |i| [values[i], -i] }
  end

  def argmin(values)
    values.each_index.min_by { |i| [values[i], i] }
  end

  class Statistics
    include Linalg

    attr_reader :row_count, :feature_count, :counts, :means, :scatter, :center, :variances

    def initialize(rows, features, class_count)
      @row_count = rows.length
      @feature_count = features.length
      groups = Array.new(class_count) { [] }
      vectors = rows.map do |row|
        vector = features.map { |j| row.values[j] }
        groups[row.class_index] << vector
        vector
      end
      @counts = groups.map(&:length)
      @means = groups.map do |group|
        Array.new(@feature_count) { |j| total(group.map { |vector| vector[j] }) / group.length }
      end
      @scatter = groups.each_with_index.map do |group, k|
        Array.new(@feature_count) do |a|
          Array.new(@feature_count) do |b|
            total(group.map { |vector| (vector[a] - @means[k][a]) * (vector[b] - @means[k][b]) })
          end
        end
      end
      @center = Array.new(@feature_count) { |j| total(vectors.map { |vector| vector[j] }) / @row_count }
      @variances = Array.new(@feature_count) do |j|
        total(vectors.map { |vector| (vector[j] - @center[j]) * (vector[j] - @center[j]) }) / @row_count
      end
    end

    def pooled_covariance
      divisor = @row_count - @counts.length
      Array.new(@feature_count) do |a|
        Array.new(@feature_count) { |b| total(@scatter.map { |matrix| matrix[a][b] }) / divisor }
      end
    end
  end

  class Model
    include Linalg

    attr_reader :name, :features, :statistics, :means, :epsilon, :gamma, :priors,
                :max_variance, :added_variance, :covariances, :factors, :log_determinants

    def initialize(name, features, statistics, prior_mode, epsilon, gamma)
      @name, @features, @statistics = name, features.dup.freeze, statistics
      @means, @epsilon, @gamma = statistics.means, epsilon, gamma
      class_count = statistics.counts.length
      @priors = if prior_mode == 'empirical'
                  statistics.counts.map { |count| count.fdiv(statistics.row_count) }
                else
                  Array.new(class_count, 1.0 / class_count)
                end
      @max_variance = statistics.variances.max
      @added_variance = epsilon * @max_variance
      @covariances = if name == 'LDA'
                       Array.new(class_count, statistics.pooled_covariance)
                     else
                       statistics.counts.each_with_index.map do |count, k|
                         Array.new(features.length) do |a|
                           Array.new(features.length) do |b|
                             if name == 'NB'
                               a == b ? statistics.scatter[k][a][b] / count + @added_variance : 0.0
                             else
                               value = statistics.scatter[k][a][b] / (count - 1)
                               a == b ? value : value * (1 - gamma)
                             end
                           end
                         end
                       end
                     end
      if name == 'LDA'
        lower = cholesky(@covariances.first)
        @factors = Array.new(class_count, lower)
        @log_determinants = Array.new(class_count, log_determinant(lower))
      else
        @factors = @covariances.map { |matrix| cholesky(matrix) }
        @log_determinants = @factors.map { |lower| log_determinant(lower) }
      end
      @log_priors = @priors.map { |prior| Math.log(prior) }
      @normalizer = features.length * Math.log(2 * Math::PI) / 2
    end

    def vector(values)
      @features.map { |j| values[j] }
    end

    def squared_distances(vector)
      @means.each_with_index.map do |mean, k|
        difference = vector.zip(mean).map { |value, center| value - center }
        quadratic_form(@factors[k], difference)
      end
    end

    def distances(values)
      squared_distances(vector(values))
    end

    def scores(vector)
      squared_distances(vector).each_with_index.map do |distance, k|
        @log_priors[k] - @normalizer - @log_determinants[k] / 2 - distance / 2
      end
    end

    def predict_vector(vector)
      GaussianModels.argmax(scores(vector))
    end

    def predict(values)
      predict_vector(vector(values))
    end

    def infer_vector(vector, costs = nil)
      scores = scores(vector)
      predicted = GaussianModels.argmax(scores)
      maximum = scores[predicted]
      exponentials = scores.map { |score| Math.exp(score - maximum) }
      sum = total(exponentials)
      probabilities = exponentials.map { |value| value / sum }
      log_sum = Math.log(sum)
      log_probabilities = scores.map { |score| (score - maximum) - log_sum }
      decision = predicted
      if costs
        risks = Array.new(scores.length) do |b|
          total(probabilities.each_with_index.map { |probability, k| probability * costs[k][b] })
        end
        decision = GaussianModels.argmin(risks)
      end
      Prediction.new(predicted, probabilities, log_probabilities, probabilities.max, decision)
    end

    def infer(values, costs = nil)
      infer_vector(vector(values), costs)
    end
  end

  def train(rows, features, class_count, name, prior_mode, epsilon, gamma)
    Model.new(name, features, Statistics.new(rows, features, class_count), prior_mode, epsilon, gamma)
  end
end

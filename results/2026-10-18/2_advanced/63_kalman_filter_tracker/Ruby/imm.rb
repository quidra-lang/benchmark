require_relative 'kalman'

class IMM
  attr_reader :probabilities

  def initialize(densities, transition, initial, sigma, velocity_variance, measurement)
    @models = densities.map { |q| Kalman.new('CV', q, sigma, velocity_variance, 0.0, measurement) }
    @transition = [transition.take(2), transition.drop(2)]
    @probabilities = initial.dup
  end

  def step(interval, measurement)
    mu = @probabilities
    predicted = 2.times.map { |j| @transition[0][j] * mu[0] + @transition[1][j] * mu[1] }
    old_states, old_covariances = @models.map(&:x), @models.map(&:p)
    likelihoods = @models.each_with_index.map do |model, j|
      w0 = @transition[0][j] * mu[0] / predicted[j]
      w1 = @transition[1][j] * mu[1] / predicted[j]
      mixed = 4.times.map { |r| w0 * old_states[0][r] + w1 * old_states[1][r] }
      covariance = 4.times.map do |r|
        4.times.map do |s|
          w0 * (old_covariances[0][r][s] + (old_states[0][r] - mixed[r]) * (old_states[0][s] - mixed[s])) +
            w1 * (old_covariances[1][r][s] + (old_states[1][r] - mixed[r]) * (old_states[1][s] - mixed[s]))
        end
      end
      model.x, model.p = mixed, covariance
      model.predict(interval)
      if measurement
        distance2, _, innovation_covariance = model.update(measurement)
        Math.exp(-distance2 / 2.0) / (2 * Math::PI * Math.sqrt(Mat.determinant2(innovation_covariance)))
      else
        1.0
      end
    end
    denominator = likelihoods[0] * predicted[0] + likelihoods[1] * predicted[1]
    @probabilities = 2.times.map { |j| likelihoods[j] * predicted[j] / denominator }
  end

  def estimate
    4.times.map { |r| @probabilities[0] * @models[0].x[r] + @probabilities[1] * @models[1].x[r] }
  end
end

module Selection
  # Enumerable#sum may compensate floating-point additions; the task requires
  # a simple accumulation from zero in the sequence's original order.
  def self.sum(values)
    values.inject(0.0) do |total, value|
      total + (block_given? ? yield(value) : value)
    end
  end

  def self.cross_validation(observed, predicted)
    return nil if predicted.any?(&:nil?)

    rss = sum(observed.each_index) do |i|
      error = observed[i] - predicted[i]
      error * error
    end
    rss / observed.length
  end

  def self.generalized(observed, fitted, edf)
    rss = sum(observed.each_index) do |i|
      error = observed[i] - fitted[i]
      error * error
    end
    tau = 1 - edf / observed.length
    rss / observed.length / (tau * tau)
  end

  def self.choose(candidates)
    candidates.each_index.reject { |i| candidates[i][:score].nil? }
              .min_by { |i| [candidates[i][:score], i] }
  end
end

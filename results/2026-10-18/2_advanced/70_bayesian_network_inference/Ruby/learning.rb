module Learning
  def self.total(values)
    values.inject(0.0) { |result, value| result + value }
  end

  def self.parent_row(parents, assignment, sizes)
    parents.inject(0) { |row, parent| row * sizes[parent] + assignment[parent] }
  end

  def self.count_samples(variable, parents, samples, sizes)
    rows = parents.inject(1) { |product, parent| product * sizes[parent] }
    counts = Array.new(rows) { Array.new(sizes[variable], 0) }
    samples.each { |sample| counts[parent_row(parents, sample, sizes)][sample[variable]] += 1 }
    counts
  end

  def self.learn(counts, alpha)
    counts.map do |row|
      denominator = total(row.map { |count| count + alpha })
      row.map { |count| (count + alpha) / denominator }
    end
  end

  def self.log_likelihood(counts, cpt)
    likelihood = 0.0
    counts.zip(cpt).each do |row, probabilities|
      row.zip(probabilities).each do |count, probability|
        likelihood += count * Math.log(probability) unless count.zero?
      end
    end
    likelihood
  end

  def self.parameter_count(counts)
    (counts[0].length - 1) * counts.length
  end

  def self.family_score(variable, parents, samples, sizes, alpha)
    counts = count_samples(variable, parents.sort, samples, sizes)
    log_likelihood(counts, learn(counts, alpha)) - parameter_count(counts) * Math.log(samples.length) / 2
  end
end

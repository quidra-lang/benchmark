require_relative 'learning'

module Sampling
  class Minstd
    def initialize(seed)
      @state = seed
    end

    def uniform
      @state = 48_271 * @state % 2_147_483_647
      @state.to_f / 2_147_483_647
    end
  end

  def self.choose(probabilities, random)
    uniform, cumulative = random.uniform, 0.0
    probabilities.each_with_index do |probability, state|
      cumulative += probability
      return state if uniform < cumulative
    end
    probabilities.length - 1
  end

  def self.weighted_sample(topological, parents, cpts, sizes, evidence, random)
    sample, weight = Array.new(sizes.length, 0), 1.0
    topological.each do |variable|
      row = cpts[variable][Learning.parent_row(parents[variable], sample, sizes)]
      if evidence.key?(variable)
        sample[variable] = evidence[variable]
        weight *= row[evidence[variable]]
      else
        sample[variable] = choose(row, random)
      end
    end
    [sample, weight]
  end
end

module HMM
  class MINSTD
    def initialize(seed)
      @state = seed
    end

    def random
      @state = (48271 * @state) % 2147483647
      @state / 2147483647.0
    end
  end

  def draw(weights, generator)
    total = ordered_sum(weights)
    threshold = generator.random * total
    cumulative = 0.0
    weights.each_with_index do |weight, i|
      cumulative += weight
      return i if threshold < cumulative
    end
    weights.length - 1
  end

  def synthetic_sequence(model, length, generator)
    states, observations = [], []
    length.times do |t|
      weights = t.zero? ? model.initial : model.transition[states[-1]]
      state = draw(weights, generator)
      states << state
      observations << draw(model.emission[state], generator)
    end
    [states, observations]
  end

  def posterior_path(model, forward, generator)
    path = Array.new(forward.length, 0)
    path[-1] = draw(forward[-1], generator)
    (path.length - 2).downto(0) do |t|
      weights = Array.new(model.states.length) { |i| forward[t][i] * model.transition[i][path[t + 1]] }
      path[t] = draw(weights, generator)
    end
    path
  end
end

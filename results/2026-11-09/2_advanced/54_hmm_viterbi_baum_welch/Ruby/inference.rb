module HMM
  Forward = Struct.new(:values, :scales, :emissions, :loglik)
  ForwardBackward = Struct.new(:forward, :backward, :scales, :emissions, :posterior, :loglik)
  Decoding = Struct.new(:viterbi, :viterbi_logprob, :posterior, :confidence, :fb)

  def maximum_index(values)
    best = 0
    (1...values.length).each { |i| best = i if values[i] > values[best] }
    best
  end

  def emission_factors(model, observation)
    model.emission.map { |row| observation == -1 ? 1.0 : row[observation] }
  end

  def log_emission_factors(model, observation)
    model.emission.map { |row| observation == -1 ? 0.0 : Math.log(row[observation]) }
  end

  def scaled_forward(model, observations)
    k = model.states.length
    emissions = observations.map { |c| emission_factors(model, c) }
    values, scales, loglik = [], [], 0.0
    emissions.each_with_index do |factors, t|
      unscaled = Array.new(k) do |j|
        if t.zero?
          model.initial[j] * factors[j]
        else
          total = 0.0
          k.times { |i| total += values[t - 1][i] * model.transition[i][j] }
          total * factors[j]
        end
      end
      scale = ordered_sum(unscaled)
      scales << scale
      values << unscaled.map { |value| value / scale }
      loglik += Math.log(scale)
    end
    Forward.new(values, scales, emissions, loglik)
  end

  def forward_backward(model, observations)
    f = scaled_forward(model, observations)
    k, length = model.states.length, observations.length
    backward = Array.new(length) { Array.new(k, 0.0) }
    backward[-1] = Array.new(k, 1.0)
    (length - 2).downto(0) do |t|
      k.times do |i|
        total = 0.0
        k.times { |j| total += model.transition[i][j] * f.emissions[t + 1][j] * backward[t + 1][j] }
        backward[t][i] = total / f.scales[t + 1]
      end
    end
    posterior = Array.new(length) { |t| Array.new(k) { |i| f.values[t][i] * backward[t][i] } }
    ForwardBackward.new(f.values, backward, f.scales, f.emissions, posterior, f.loglik)
  end

  def posterior_transition(model, result, t, i, j)
    result.forward[t][i] * model.transition[i][j] * result.emissions[t + 1][j] *
      result.backward[t + 1][j] / result.scales[t + 1]
  end

  def viterbi(model, observations)
    k = model.states.length
    transitions = model.transition.map { |row| row.map { |v| Math.log(v) } }
    factors = log_emission_factors(model, observations[0])
    scores = Array.new(k) { |i| Math.log(model.initial[i]) + factors[i] }
    predecessors = [Array.new(k, 0)]
    observations.drop(1).each do |c|
      factors = log_emission_factors(model, c)
      previous_states = []
      next_scores = Array.new(k) do |j|
        candidates = Array.new(k) { |i| scores[i] + transitions[i][j] }
        previous = maximum_index(candidates)
        previous_states << previous
        candidates[previous] + factors[j]
      end
      predecessors << previous_states
      scores = next_scores
    end
    path = Array.new(observations.length, 0)
    path[-1] = maximum_index(scores)
    logprob = scores[path[-1]]
    (path.length - 1).downto(1) { |t| path[t - 1] = predecessors[t][path[t]] }
    [path, logprob]
  end

  def decode(model, observations)
    fb = forward_backward(model, observations)
    path, logprob = viterbi(model, observations)
    posterior = fb.posterior.map { |row| maximum_index(row) }
    confidence = fb.posterior.each_with_index.map { |row, t| row[posterior[t]] }
    Decoding.new(path, logprob, posterior, confidence, fb)
  end
end

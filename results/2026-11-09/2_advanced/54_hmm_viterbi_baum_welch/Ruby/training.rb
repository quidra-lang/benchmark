module HMM
  def smoothed_model(template, name, initial, transition, emission, alpha)
    Model.new(name, template.states, template.symbols, template.missing,
              initial.map { |v| v + alpha }, transition.map { |row| row.map { |v| v + alpha } },
              emission.map { |row| row.map { |v| v + alpha } })
  end

  def baum_welch_step(model, sequences, pseudocount)
    k = model.states.length
    initial = Array.new(k, 0.0)
    transition = Array.new(k) { Array.new(k, 0.0) }
    emission = Array.new(k) { Array.new(model.symbols.length, 0.0) }
    sequences.each do |observations|
      result = forward_backward(model, observations)
      k.times { |i| initial[i] += result.posterior[0][i] }
      observations.each_with_index do |c, t|
        k.times do |i|
          emission[i][c] += result.posterior[t][i] unless c == -1
          if t + 1 < observations.length
            k.times { |j| transition[i][j] += posterior_transition(model, result, t, i, j) }
          end
        end
      end
    end
    smoothed_model(model, 'BAUM_WELCH', initial, transition, emission, pseudocount)
  end

  def estimate_by_counting(template, pairs, alpha, name = 'SUPERVISED')
    k = template.states.length
    initial = Array.new(k, 0)
    transition = Array.new(k) { Array.new(k, 0) }
    emission = Array.new(k) { Array.new(template.symbols.length, 0) }
    pairs.each do |observations, path|
      initial[path[0]] += 1
      path.each_with_index do |i, t|
        c = observations[t]
        emission[i][c] += 1 unless c == -1
        transition[i][path[t + 1]] += 1 if t + 1 < path.length
      end
    end
    smoothed_model(template, name, initial, transition, emission, alpha)
  end

  def total_loglik(model, sequences)
    total = 0.0
    sequences.each { |observations| total += scaled_forward(model, observations).loglik }
    total
  end
end

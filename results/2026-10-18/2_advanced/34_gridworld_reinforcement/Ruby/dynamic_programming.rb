module DynamicProgramming
  module_function

  def first_max(values)
    values.index(values.max)
  end

  def bellman(environment, values, gamma, state, action)
    total = environment.transitions[state][action].sum do |cell, numerator|
      target = environment.world.state_index[cell]
      future = target.nil? ? 0 : (gamma * values[target]).div(100)
      numerator * (10_000 * environment.reward(cell) + future)
    end
    total.div(environment.slip_total)
  end

  def action_values(environment, values, gamma, state)
    Array.new(4) { |action| bellman(environment, values, gamma, state, action) }
  end

  def greedy_policy(environment, values, gamma)
    values.each_index.map { |state| first_max(action_values(environment, values, gamma, state)) }
  end

  def value_iteration(environment, gamma, theta)
    values = Array.new(environment.world.states.length, 0)
    changes = []
    loop do
      updated = values.each_index.map { |state| action_values(environment, values, gamma, state).max }
      delta = values.each_index.map { |state| (updated[state] - values[state]).abs }.max
      changes << delta
      values = updated
      return [values, changes] if delta <= theta
    end
  end

  def in_place_value_iteration(environment, gamma, theta)
    values = Array.new(environment.world.states.length, 0)
    sweeps = 0
    loop do
      sweeps += 1
      delta = 0
      values.each_index do |state|
        value = action_values(environment, values, gamma, state).max
        delta = [delta, (value - values[state]).abs].max
        values[state] = value
      end
      return [values, sweeps] if delta <= theta
    end
  end

  def evaluate_policy(environment, policy, initial, gamma, theta)
    values = initial.dup
    sweeps = 0
    loop do
      sweeps += 1
      delta = 0
      policy.each_with_index do |action, state|
        value = bellman(environment, values, gamma, state, action)
        delta = [delta, (value - values[state]).abs].max
        values[state] = value
      end
      return [values, sweeps] if delta <= theta
    end
  end

  def policy_iteration(environment, gamma, theta)
    policy = Array.new(environment.world.states.length, 0)
    values = Array.new(policy.length, 0)
    rounds = []
    loop do
      values, sweeps = evaluate_policy(environment, policy, values, gamma, theta)
      improved = greedy_policy(environment, values, gamma)
      changes = policy.each_index.count { |state| improved[state] != policy[state] }
      rounds << [sweeps, changes, values[environment.world.start_state]]
      policy = improved
      return [policy, values, rounds] if changes.zero?
    end
  end
end

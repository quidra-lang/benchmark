require_relative "dynamic_programming"

module TDLearning
  module_function

  def choose(generator, q_row, epsilon)
    return generator.draw % 4 if generator.draw % 1000 < epsilon

    DynamicProgramming.first_max(q_row)
  end

  def td_target(reward, terminal, next_value, gamma)
    10_000 * reward + (terminal ? 0 : (gamma * next_value).div(100))
  end

  def next_value(q_row, epsilon = nil)
    return q_row.max if epsilon.nil?

    (epsilon * q_row.sum + 4 * (1000 - epsilon) * q_row.max).div(4000)
  end

  def td_update(q_row, action, target, alpha)
    q_row[action] += (alpha * (target - q_row[action])).div(100)
  end
end

class DynaModel
  include TDLearning

  def initialize(state_count)
    @outcomes = Array.new(state_count) { Array.new(4) }
    @pairs = []
  end

  def record(state, action, reward, next_state)
    @pairs << [state, action] if @outcomes[state][action].nil?
    @outcomes[state][action] = [reward, next_state]
  end

  def plan(generator, q_values, gamma, alpha, count)
    count.times do
      state, action = @pairs[generator.draw % @pairs.length]
      reward, next_state = @outcomes[state][action]
      terminal = next_state.nil?
      future = terminal ? 0 : next_value(q_values[next_state])
      td_update(q_values[state], action, td_target(reward, terminal, future, gamma), alpha)
    end
  end
end

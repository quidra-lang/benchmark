module MonteCarlo
  module_function

  def discounted_return(rewards, gamma)
    rewards.reverse_each.reduce(0) { |value, reward| 10_000 * reward + (gamma * value).div(100) }
  end
end

class ReturnAverages
  def initialize(state_count)
    @sums = Array.new(state_count) { Array.new(4, 0) }
    @counts = Array.new(state_count) { Array.new(4, 0) }
  end

  def update(q_values, history, gamma)
    first = {}
    history.each_with_index { |(state, action, _), index| first[[state, action]] ||= index }
    value = 0
    (history.length - 1).downto(0) do |index|
      state, action, reward = history[index]
      value = 10_000 * reward + (gamma * value).div(100)
      next unless first[[state, action]] == index

      @sums[state][action] += value
      @counts[state][action] += 1
      q_values[state][action] = @sums[state][action].div(@counts[state][action])
    end
  end
end

# frozen_string_literal: true

module RunRules
  LENGTHS = {1 => 1, 2 => 3, 3 => 5, 4 => 8, 5 => 6, 6 => 14, 7 => 15, 8 => 8}.freeze
  Signal = Struct.new(:chart, :rule, :start, :finish, :value, :direction, keyword_init: true)

  module_function

  def zones(limits)
    upper = (limits.ucl - limits.cl) / 3
    lower = (limits.cl - limits.lcl) / 3
    {u1: limits.cl + upper, u2: limits.cl + 2 * upper,
     l1: limits.cl - lower, l2: limits.cl - 2 * lower}
  end

  def direction(rule, values, limits, bounds)
    last = values[-1]
    case rule
    when 1
      return last > limits.cl ? 'UP' : 'DOWN' if limits.outside?(last)
    when 2
      return 'UP' if last > bounds[:u2] && values.count { |value| value > bounds[:u2] } >= 2
      return 'DOWN' if last < bounds[:l2] && values.count { |value| value < bounds[:l2] } >= 2
    when 3
      return 'UP' if last > bounds[:u1] && values.count { |value| value > bounds[:u1] } >= 4
      return 'DOWN' if last < bounds[:l1] && values.count { |value| value < bounds[:l1] } >= 4
    when 4
      return 'UP' if values.all? { |value| value > limits.cl }
      return 'DOWN' if values.all? { |value| value < limits.cl }
    when 5
      return 'UP' if values.each_cons(2).all? { |first, second| second > first }
      return 'DOWN' if values.each_cons(2).all? { |first, second| second < first }
    when 6
      differences = values.each_cons(2).map { |first, second| second - first }
      if differences.none?(&:zero?) && differences.each_cons(2).all? { |first, second| first.positive? != second.positive? }
        return 'NONE'
      end
    when 7
      return 'NONE' if values.all? { |value| bounds[:l1] < value && value < bounds[:u1] }
    when 8
      if values.all? { |value| value > bounds[:u1] || value < bounds[:l1] } &&
         values.any? { |value| value > bounds[:u1] } && values.any? { |value| value < bounds[:l1] }
        return 'NONE'
      end
    end
    nil
  end

  def check(chart, sequence, limits, rules)
    bounds = zones(limits)
    signals = []
    sequence.each_with_index do |(point, value), index|
      rules.each do |rule|
        length = LENGTHS.fetch(rule)
        next if index + 1 < length

        window = sequence[index - length + 1, length]
        side = direction(rule, window.map(&:last), limits, bounds)
        next if side.nil?

        signals << Signal.new(chart: chart, rule: rule, start: window[0][0], finish: point,
                              value: value, direction: side)
      end
    end
    signals
  end

  def zone(value, limits)
    bounds = zones(limits)
    return 'OUT+' if value > limits.ucl
    return 'OUT-' if value < limits.lcl
    return 'A+' if value > bounds[:u2]
    return 'B+' if value > bounds[:u1]
    return 'C+' if value > limits.cl
    return 'A-' if value < bounds[:l2]
    return 'B-' if value < bounds[:l1]
    return 'C-' if value < limits.cl

    'C0'
  end
end

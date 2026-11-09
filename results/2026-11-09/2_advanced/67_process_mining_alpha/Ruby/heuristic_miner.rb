require_relative 'dfg'

module HeuristicMiner
  module_function

  def dependency(counts, a, b)
    forward, reverse = Dfg.count(counts, a, b), Dfg.count(counts, b, a)
    Rational(forward - reverse, forward + reverse + 1)
  end

  def loop_measure(observations)
    Rational(observations, observations + 1)
  end

  def routing_measure(counts, activity, a, b, split)
    numerator = Dfg.count(counts, a, b) + Dfg.count(counts, b, a)
    denominator = split ? Dfg.count(counts, activity, a) + Dfg.count(counts, activity, b) + 1 :
                          Dfg.count(counts, a, activity) + Dfg.count(counts, b, activity) + 1
    Rational(numerator, denominator)
  end
end

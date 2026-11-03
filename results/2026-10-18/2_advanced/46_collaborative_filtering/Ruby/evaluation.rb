# Ordinary additions preserve the specified order; Array#sum compensates floats.
module Evaluation
  module_function

  def ordered_sum(values)
    total = 0.0
    values.each { |value| total += (block_given? ? yield(value) : value) }
    total
  end

  def clip(prediction)
    return 1.0 if prediction < 1
    return 5.0 if prediction > 5

    prediction
  end

  def rmse(errors)
    return nil if errors.empty?

    Math.sqrt(ordered_sum(errors) { |error| error * error } / errors.size)
  end

  def mae(errors)
    return nil if errors.empty?

    ordered_sum(errors, &:abs) / errors.size
  end

  def training_rmse(training)
    total = 0.0
    training.each do |user, item, rating, _time|
      error = rating - yield(user, item)
      total += error * error
    end
    Math.sqrt(total / training.size)
  end

  def rank_weight(rank)
    1.0 / Math.log2(rank + 1)
  end

  def ranking_metrics(ranked, relevant, cutoff)
    hits = 0
    dcg = average_precision = reciprocal_rank = 0.0
    ranked.first(cutoff).each_with_index do |item, index|
      next unless relevant.include?(item)

      rank = index + 1
      hits += 1
      dcg += rank_weight(rank)
      average_precision += hits.to_f / rank
      reciprocal_rank = 1.0 / rank if reciprocal_rank.zero?
    end
    ideal_hits = [cutoff, relevant.size].min
    ideal_dcg = ordered_sum(1..ideal_hits) { |rank| rank_weight(rank) }
    [hits, hits.to_f / relevant.size, dcg / ideal_dcg,
     average_precision / ideal_hits, reciprocal_rank]
  end
end

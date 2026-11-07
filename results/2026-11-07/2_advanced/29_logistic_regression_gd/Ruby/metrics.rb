module Metrics
  def self.real(value, digits = 4)
    text = format("%.#{digits}f", value)
    text.match?(/\A-0\.0+\z/) ? text[1..] : text
  end

  def self.ratio(numerator, denominator)
    return '-' if denominator.zero?

    rounded = (20_000 * numerator + denominator) / (2 * denominator)
    "#{rounded / 10_000}.#{(rounded % 10_000).to_s.rjust(4, '0')}"
  end

  def self.fraction(pair)
    numerator, denominator = pair
    divisor = numerator.gcd(denominator)
    "#{numerator / divisor}/#{denominator / divisor} #{ratio(numerator, denominator)}"
  end

  def self.confusion(probabilities, targets, threshold)
    counts = { tp: 0, fp: 0, tn: 0, fn: 0 }
    probabilities.each_with_index do |probability, index|
      if probability >= threshold
        counts[targets[index] == 1 ? :tp : :fp] += 1
      else
        counts[targets[index] == 1 ? :fn : :tn] += 1
      end
    end
    counts
  end

  def self.auc(scores, targets)
    order = scores.each_index.sort_by { |index| [scores[index], index] }
    rank_total = 0
    cursor = 0
    while cursor < order.length
      finish = cursor + 1
      finish += 1 while finish < order.length && scores[order[finish]] == scores[order[cursor]]
      doubled_rank = cursor + 1 + finish
      (cursor...finish).each do |index|
        rank_total += doubled_rank if targets[order[index]] == 1
      end
      cursor = finish
    end
    positive = targets.count(1)
    negative = targets.length - positive
    [rank_total - positive * (positive + 1), 2 * positive * negative]
  end

  def self.roc(probabilities, targets)
    order = probabilities.each_index.sort_by { |index| [-probabilities[index], index] }
    points = []
    true_positive = false_positive = 0
    cursor = 0
    while cursor < order.length
      probability = probabilities[order[cursor]]
      finish = cursor
      while finish < order.length && probabilities[order[finish]] == probability
        if targets[order[finish]] == 1
          true_positive += 1
        else
          false_positive += 1
        end
        finish += 1
      end
      points << [probability, true_positive, false_positive]
      cursor = finish
    end
    points
  end
end

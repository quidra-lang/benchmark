module Boosting
  module_function

  def number(value, decimals = 4)
    result = format("%.*f", decimals, value)
    result.start_with?('-') && result.to_f.zero? ? result[1..] : result
  end

  def ratio(numerator, denominator)
    denominator.positive? ? number(numerator.to_f / denominator) : '-'
  end

  def prediction(score)
    score.positive? ? 1 : -1
  end

  def auc(rows, scores)
    positives = rows.each_index.filter_map { |i| scores[i] if rows[i].label == 1 }
    negatives = rows.each_index.filter_map { |i| scores[i] if rows[i].label == -1 }
    wins = 0
    ties = 0
    positives.each do |positive|
      negatives.each do |negative|
        wins += 1 if positive > negative
        ties += 1 if positive == negative
      end
    end
    [2 * wins + ties, 2 * positives.length * negatives.length]
  end

  def confusion(rows, predictions, classes)
    matrix = Array.new(classes) { Array.new(classes, 0) }
    rows.each_with_index { |row, i| matrix[row.label - 1][predictions[i] - 1] += 1 }
    matrix
  end

  def count_at_most(margins, threshold)
    margins.count { |margin| margin <= threshold }
  end

  def write_lines(path, lines)
    File.open(path, 'w:US-ASCII') do |destination|
      lines.each { |line| destination.write(line, "\n") }
    end
  end
end

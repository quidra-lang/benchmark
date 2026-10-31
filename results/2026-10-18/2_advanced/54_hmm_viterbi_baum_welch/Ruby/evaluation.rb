module HMM
  def fraction(numerator, denominator)
    return '-' if denominator.zero?
    numerator, denominator = -numerator, -denominator if denominator.negative?
    divisor = numerator.abs.gcd(denominator)
    "#{numerator / divisor}/#{denominator / divisor}"
  end

  def confusion_matrix(k)
    Array.new(k) { Array.new(k, 0) }
  end

  def accumulate_confusion(matrix, truth, prediction)
    truth.zip(prediction).each { |actual, predicted| matrix[actual][predicted] += 1 }
  end

  def correct_count(truth, prediction)
    truth.zip(prediction).count { |actual, predicted| actual == predicted }
  end

  def matrix_lines(states, matrix)
    width = matrix.flatten.map { |v| v.to_s.length }.max
    [' ' + states.map { |state| ' ' + state.rjust(width) }.join] +
      states.zip(matrix).map { |state, row| state + row.map { |v| ' ' + v.to_s.rjust(width) }.join }
  end

  def metric_lines(states, matrix)
    k = states.length
    rows = matrix.map { |row| ordered_sum(row) }
    columns = Array.new(k) { |j| ordered_sum(matrix.map { |row| row[j] }) }
    total = ordered_sum(rows)
    correct = ordered_sum(Array.new(k) { |i| matrix[i][i] })
    expected = ordered_sum(Array.new(k) { |i| rows[i] * columns[i] })
    lines = ["ACCURACY #{fraction(correct, total)}",
             "KAPPA #{fraction(total * correct - expected, total * total - expected)}"]
    states.each_with_index do |state, i|
      tp = matrix[i][i]
      lines << "STATE #{state} precision #{fraction(tp, columns[i])} recall #{fraction(tp, rows[i])} f1 #{fraction(2 * tp, columns[i] + rows[i])}"
    end
    lines
  end

  def runs(path)
    return [] if path.empty?
    result, start, state = [], 1, path[0]
    (1...path.length).each do |t|
      next if path[t] == state
      result << [state, start, t]
      state, start = path[t], t + 1
    end
    result << [state, start, path.length]
  end

  def regions_overlap(first, second)
    first[0] <= second[1] && second[0] <= first[1]
  end

  def region_counts(predicted, truth)
    [predicted.length, truth.length,
     predicted.count { |region| truth.any? { |other| regions_overlap(region, other) } },
     truth.count { |region| predicted.any? { |other| regions_overlap(region, other) } }]
  end

  def boundaries(path)
    (1...path.length).select { |t| path[t - 1] != path[t] }.map { |t| t + 1 }
  end

  def boundary_counts(predicted_path, true_path, tolerance)
    predicted, truth = boundaries(predicted_path), boundaries(true_path)
    [predicted.length, truth.length,
     predicted.count { |t| truth.any? { |other| (t - other).abs <= tolerance } },
     truth.count { |t| predicted.any? { |other| (t - other).abs <= tolerance } }]
  end
end

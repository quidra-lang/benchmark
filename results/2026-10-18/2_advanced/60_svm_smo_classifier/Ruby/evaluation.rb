module Evaluation
  def sign(value) = value > 0 ? 1 : -1

  def fixed(value, decimals = 4)
    result = format("%.#{decimals}f", value)
    result.start_with?('-') && result.to_f.zero? ? result[1..] : result
  end

  def ratio(a, b) = b > 0 ? fixed(a.to_f / b) : '-'
  def correct_count(labels, values) = labels.zip(values).count { |y, v| sign(v) == y }
  def folds(size, count)
    count.times.map { |f| [(0...size).reject { |i| i % count == f }, (0...size).select { |i| i % count == f }] }
  end

  def binary_counts(labels, values)
    counts = [0, 0, 0, 0]
    labels.zip(values).each do |y, v|
      index = y == 1 ? (sign(v) == 1 ? 0 : 3) : (sign(v) == 1 ? 1 : 2)
      counts[index] += 1
    end
    counts
  end

  def auc(labels, values)
    positive = labels.each_index.select { |i| labels[i] == 1 }
    negative = labels.each_index.select { |i| labels[i] == -1 }
    total = 0.0
    positive.each do |i|
      negative.each { |j| total += values[i] > values[j] ? 1.0 : (values[i] == values[j] ? 0.5 : 0.0) }
    end
    total / (positive.size * negative.size)
  end

  def confusion_matrix(classes, predictions)
    matrix = Array.new(3) { Array.new(3, 0) }
    classes.zip(predictions).each { |y, p| matrix[y - 1][p - 1] += 1 }
    matrix
  end

  def confusion_lines(matrix)
    matrix.map { |row| row.join(' ') } + 3.times.map do |i|
      "class #{i + 1} precision #{ratio(matrix[i][i], matrix.sum { |r| r[i] })} recall #{ratio(matrix[i][i], matrix[i].sum)}"
    end
  end

  def write_lines(path, lines) = File.write(path, lines.join("\n") + "\n")
end

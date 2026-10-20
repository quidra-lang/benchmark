module Evaluation
  def real(value, places = 4)
    text = format("%.#{places}f", value)
    text.start_with?('-') && text.to_f.zero? ? text[1..] : text
  end

  def ratio(a, b)
    return '-' if b.zero?
    q = (20_000 * a + b) / (2 * b)
    format('%d.%04d', q / 10_000, q % 10_000)
  end

  def best_two(scores) = scores.each_index.sort_by { |i| [-scores[i], i] }.first(2)

  def confusion(outcomes, classes)
    table = Array.new(classes) { Array.new(classes, 0) }
    outcomes.each { |o| table[o[:label]][o[:predicted]] += 1 }
    table
  end

  def class_measures(table, k)
    support, predicted, true_count = table[k].sum, table.sum { |row| row[k] }, table[k][k]
    "class #{k} support #{support} predicted #{predicted} precision #{ratio(true_count, predicted)} recall #{ratio(true_count, support)} f1 #{ratio(2 * true_count, support + predicted)}"
  end

  def level_maps(levels, width, height)
    height.times.map { |r| levels.map { |map| map[r * width, width].join }.join(' ') }
  end

  def ascii_image(pixels, width) = pixels.tr('01', '.#').chars.each_slice(width).map(&:join)
end

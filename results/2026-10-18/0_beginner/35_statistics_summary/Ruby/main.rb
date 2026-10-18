values = [72, 85, 64, 90, 85, 58, 77, 85, 69, 93, 71]
ordered = values.sort
mean = values.sum.fdiv(values.length)
squares = 0.0
values.each do |value|
  difference = value - mean
  squares += difference * difference
end
stdev = Math.sqrt(squares / values.length)
counts = values.tally
mode = counts.keys.min_by { |n| [-counts[n], n] }
puts format('mean: %.3f', mean.round(3, half: :up))
puts "median: #{ordered[values.length / 2]}"
puts "mode: #{mode}"
puts "range: #{ordered[-1] - ordered[0]}"
puts format('stdev: %.3f', stdev.round(3, half: :up))

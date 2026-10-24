state = 12345
counts = Array.new(13, 0)
1000.times do
  state = state * 48271 % 2147483647
  first = state % 6 + 1
  state = state * 48271 % 2147483647
  second = state % 6 + 1
  counts[first + second] += 1
end
(2..12).each { |total| puts "#{total}: #{counts[total]}" }
most = (2..12).max_by { |n| counts[n] }
puts "most frequent: #{most}"

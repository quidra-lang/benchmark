values = [27, 64, 13, 88, 41, 5, 72, 36]
swaps = 0
(1...values.length).each do |p|
  changed = false
  (0...values.length - p).each do |j|
    if values[j] > values[j + 1]
      values[j], values[j + 1] = values[j + 1], values[j]
      swaps += 1
      changed = true
    end
  end
  puts "pass #{p}: #{values.join(' ')}"
  break unless changed
end
puts "swaps: #{swaps}"

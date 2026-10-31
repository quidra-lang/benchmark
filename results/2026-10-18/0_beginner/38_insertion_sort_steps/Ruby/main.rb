values = [52, 17, 38, 9, 61, 38, 24, 45]
total = 0
(1...values.length).each do |i|
  value, j, shifts = values[i], i - 1, 0
  while j >= 0 && values[j] > value
    values[j + 1] = values[j]
    j -= 1
    shifts += 1
  end
  values[j + 1] = value
  total += shifts
  puts "i=#{i} shifts=#{shifts}: #{values.join(' ')}"
end
puts "total shifts: #{total}"

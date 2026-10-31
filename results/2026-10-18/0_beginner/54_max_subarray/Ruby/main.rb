arrays = [
  [3, -5, 8, -2, 6, -9, 4, 1, -7, 5, -3, 2],
  [-4, 7, -1, 3, -8, 10, -2, 5, -6, -2, 9, -12, 4, -1],
  [-6, -3, 5, -1, -4, 3, -9, 2, 3, -1, 4, -5, 1, 6, -2]
]
arrays.each do |values|
  current = best = values[0]
  start = best_start = best_end = 0
  (1...values.length).each do |i|
    if current + values[i] < values[i]
      current, start = values[i], i
    else
      current += values[i]
    end
    best, best_start, best_end = current, start, i if current > best
  end
  puts "max sum #{best} at [#{best_start}, #{best_end}]"
end

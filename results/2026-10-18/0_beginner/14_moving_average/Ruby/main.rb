sales = [120, 135, 98, 143, 160, 152, 171, 149, 188, 176]
sales.each_cons(3).with_index(3) do |window, day|
  puts format('day %d: %.2f', day, window.sum.fdiv(3))
end

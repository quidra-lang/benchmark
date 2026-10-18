sales = [120, 135, 98, 143, 160, 152, 171, 149, 188, 176]
(3..sales.length).each do |day|
  average = sales[day - 3, 3].sum.fdiv(3)
  puts format('day %d: %.2f', day, average.round(2, half: :up))
end

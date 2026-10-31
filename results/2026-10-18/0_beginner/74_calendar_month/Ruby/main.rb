names = %w[January February March April May June July August September October November December]
offsets = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
[[2024, 2], [2026, 8], [2026, 11]].each_with_index do |(year, month), index|
  puts if index.positive?
  adjusted = year - (month < 3 ? 1 : 0)
  weekday = (adjusted + adjusted / 4 - adjusted / 100 + adjusted / 400 + offsets[month - 1] + 1) % 7
  leap = (year % 4).zero? && (!(year % 100).zero? || (year % 400).zero?)
  lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  puts "#{names[month - 1]} #{year}"
  puts 'Su Mo Tu We Th Fr Sa'
  fields = Array.new(weekday, '  ') + (1..lengths[month - 1]).map { |day| format('%2d', day) }
  fields.each_slice(7) { |week| puts week.join(' ') }
end

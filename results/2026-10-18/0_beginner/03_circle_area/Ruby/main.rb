pi = 3.141592653589793
[3, 7, 12, 25, 41].each do |radius|
  area = pi * radius * radius
  circumference = 2 * pi * radius
  puts format('r=%d area=%.3f circumference=%.3f', radius,
              area, circumference)
end

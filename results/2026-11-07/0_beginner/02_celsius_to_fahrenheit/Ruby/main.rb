temperatures = [-40, -15, -3, 0, 22, 37, 100]
temperatures.each do |celsius|
  fahrenheit = celsius * 1.8 + 32
  puts format('%d C = %.1f F', celsius, fahrenheit)
end

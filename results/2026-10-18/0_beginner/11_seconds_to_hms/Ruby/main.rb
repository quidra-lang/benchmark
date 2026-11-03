[0, 59, 3725, 45296, 86400, 312047].each do |total|
  hours, remaining = total.divmod(3600)
  minutes, seconds = remaining.divmod(60)
  puts format('%d seconds = %02d:%02d:%02d', total, hours, minutes, seconds)
end

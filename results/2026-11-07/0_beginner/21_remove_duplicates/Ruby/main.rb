values = [12, 5, 12, 8, 3, 5, 20, 8, 8, 15, 3, 7, 20, 12, 9]
unique = values.uniq
puts unique.join(' ')
puts "removed: #{values.length - unique.length}"

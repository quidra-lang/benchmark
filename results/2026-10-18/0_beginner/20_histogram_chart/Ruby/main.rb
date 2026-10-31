days = %w[Mon Tue Wed Thu Fri Sat Sun]
counts = [7, 12, 4, 15, 9, 18, 11]
days.zip(counts).each { |day, count| puts "#{day} | #{'*' * count} #{count}" }

scores = [78, 90, 100, 59, 80, 85, 89, 70, 45, 93]
counts = %w[A B C D F].to_h { |grade| [grade, 0] }
scores.each do |score|
  grade = score >= 90 ? 'A' : score >= 80 ? 'B' : score >= 70 ? 'C' : score >= 60 ? 'D' : 'F'
  counts[grade] += 1
  puts "#{score}: #{grade}"
end
counts.each { |grade, count| puts "#{grade}: #{count}" }

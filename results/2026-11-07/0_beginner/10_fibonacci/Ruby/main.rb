terms = [1, 1]
terms << terms[-1] + terms[-2] while terms.length < 30
puts terms.join(' ')
total = terms.sum
puts "sum: #{total}"

words = 'we planted beans and carrots in the garden behind our old house'.split(' ')
total = words.sum(&:length)
average = total.fdiv(words.length)
puts "words: #{words.length}"
puts "longest: #{words.max_by(&:length)}"
puts "shortest: #{words.min_by(&:length)}"
puts format('average length: %.2f', average)

sentence = 'Peter Piper picked a peck of pickled peppers!'
counts = sentence.downcase.scan(/[a-z]/).tally
counts.keys.sort.each { |letter| puts "#{letter}: #{counts[letter]}" }

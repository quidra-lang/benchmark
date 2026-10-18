sentence = 'Peter Piper picked a peck of pickled peppers!'
counts = Hash.new(0)
sentence.downcase.each_char { |letter| counts[letter] += 1 if ('a'..'z').cover?(letter) }
counts.keys.sort.each { |letter| puts "#{letter}: #{counts[letter]}" }

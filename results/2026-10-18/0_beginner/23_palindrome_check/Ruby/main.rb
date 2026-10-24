phrases = ['Never odd or even', 'Race a car', 'Was it a car or a cat I saw?', 'Hello, World!', 'Step on no pets.', 'No lemon, no melon']
phrases.each do |phrase|
  letters = phrase.downcase.gsub(/[^a-z]/, '')
  puts "#{phrase} -> #{letters == letters.reverse ? 'yes' : 'no'}"
end

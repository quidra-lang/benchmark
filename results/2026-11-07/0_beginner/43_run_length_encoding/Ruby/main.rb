strings = ['AAABBBCCCD', 'WWWWWWWWWWWWBWWWWWWWWWWWWBBB', 'ALGORITHM', 'MISSISSIPPI', 'XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ']
strings.each do |text|
  encoded = text.chars.chunk(&:itself).map { |char, run| "#{run.length}#{char}" }.join
  decoded = encoded.scan(/(\d+)([A-Z])/).map { |count, char| char * count.to_i }.join
  puts "#{text} -> #{encoded} -> #{decoded}"
end

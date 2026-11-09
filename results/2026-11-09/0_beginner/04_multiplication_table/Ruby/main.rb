(1..9).each do |row|
  puts (1..9).map { |column| format('%3d', row * column) }.join
end

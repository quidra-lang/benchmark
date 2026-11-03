a = [[3, -2, 5, 1], [-4, 7, 0, 6], [2, 9, -8, -3]]
b = [[1, 4], [-5, 2], [6, -1], [0, 7]]
a.each do |row|
  products = (0...2).map { |j| (0...4).sum { |k| row[k] * b[k][j] } }
  puts products.map { |n| format('%5d', n) }.join
end

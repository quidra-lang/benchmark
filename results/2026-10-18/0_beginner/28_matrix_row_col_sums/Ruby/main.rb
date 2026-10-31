matrix = [[125, 340, 78, 912, 456], [603, 27, 819, 150, 384], [0, 765, 231, 498, 62], [947, 113, 586, 39, 720]]
matrix.each { |row| puts (row + [row.sum]).map { |n| format('%6d', n) }.join }
columns = matrix.transpose.map(&:sum)
puts (columns + [columns.sum]).map { |n| format('%6d', n) }.join

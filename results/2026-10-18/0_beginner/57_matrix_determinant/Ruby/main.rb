def determinant(matrix)
  return matrix[0][0] if matrix.length == 1
  matrix[0].each_with_index.sum do |value, j|
    minor = matrix.drop(1).map { |row| row[0...j] + row.drop(j + 1) }
    term = value * determinant(minor)
    j.even? ? term : -term
  end
end

matrices = [
  [[2, -3, 1], [5, 4, -2], [-1, 6, 3]],
  [[3, 0, -2, 5], [1, 4, 7, -3], [-6, 2, 1, 8], [9, -5, 3, 2]],
  [[4, -1, 7, 0, -3], [2, 8, -5, 6, 1], [-9, 3, 2, -4, 5], [6, 0, -7, 3, -2], [1, -6, 4, 9, 8]]
]
matrices.each { |matrix| puts "det(#{matrix.length}x#{matrix.length}) = #{determinant(matrix)}" }

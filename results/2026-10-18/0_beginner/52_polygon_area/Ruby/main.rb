polygons = [
  [[0, 0], [5, 0], [6, 4], [1, 3]],
  [[2, 1], [0, 4], [3, 7], [7, 6], [8, 2]],
  [[0, 0], [8, 0], [8, 6], [5, 6], [4, 3], [3, 6], [0, 6]]
]
polygons.each_with_index do |vertices, index|
  cross_sum = 0
  perimeter = 0.0
  vertices.each_with_index do |(x, y), i|
    next_x, next_y = vertices[(i + 1) % vertices.length]
    cross_sum += x * next_y - next_x * y
    dx, dy = x - next_x, y - next_y
    perimeter += Math.sqrt(dx * dx + dy * dy)
  end
  puts format('polygon %d: area=%.1f perimeter=%.3f', index + 1, cross_sum.abs / 2.0, perimeter)
end

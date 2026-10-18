vertices = [[1, 1], [11, 2], [13, 9], [9, 7], [7, 12], [5, 6], [2, 10], [3, 5]]
points = [[4, 8], [6, 4], [10, 8], [7, 11], [14, 3], [12, 8]]
points.each do |px, py|
  crossings = 0
  vertices.each_with_index do |(x1, y1), i|
    x2, y2 = vertices[(i + 1) % vertices.length]
    if (y1 > py) != (y2 > py)
      intersection = x1 + ((x2 - x1) * (py - y1)).fdiv(y2 - y1)
      crossings += 1 if intersection > px
    end
  end
  result = crossings.odd? ? 'inside' : 'outside'
  puts "(#{px}, #{py}): #{result}"
end

points = [[12, -7], [-33, 25], [41, 18], [-8, -44], [27, 39], [-46, -12], [5, 14], [36, -29], [-19, 47], [-2, 3]]
closest = farthest = nil
points.each_index do |i|
  (i + 1...points.length).each do |j|
    dx, dy = points[i][0] - points[j][0], points[i][1] - points[j][1]
    squared = dx * dx + dy * dy
    closest = [squared, i, j] if closest.nil? || squared < closest[0]
    farthest = [squared, i, j] if farthest.nil? || squared > farthest[0]
  end
end
[['closest', closest], ['farthest', farthest]].each do |label, (squared, i, j)|
  puts format('%s: P%d P%d %.4f', label, i, j, Math.sqrt(squared))
end

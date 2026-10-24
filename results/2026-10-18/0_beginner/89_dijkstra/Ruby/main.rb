names = 'ABCDEFG'
edges = [
  [0, 1, 7], [0, 2, 3], [0, 3, 9], [1, 2, 2], [2, 4, 6], [1, 3, 3],
  [3, 4, 4], [3, 5, 5], [4, 5, 3], [4, 6, 8], [5, 6, 4]
]
graph = Array.new(names.length) { [] }
edges.each do |a, b, weight|
  graph[a] << [b, weight]
  graph[b] << [a, weight]
end
distances = Array.new(names.length, Float::INFINITY)
distances[0] = 0
done = Array.new(names.length, false)
previous = Array.new(names.length, -1)
names.length.times do
  vertex = (0...names.length).reject { |v| done[v] }.min_by { |v| [distances[v], v] }
  done[vertex] = true
  graph[vertex].each do |neighbor, weight|
    candidate = distances[vertex] + weight
    if candidate < distances[neighbor]
      distances[neighbor] = candidate
      previous[neighbor] = vertex
    end
  end
end
names.each_char.with_index do |name, target|
  path = []
  vertex = target
  while vertex >= 0
    path << names[vertex]
    vertex = previous[vertex]
  end
  puts "#{name}: distance=#{distances[target]} path=#{path.reverse.join('-')}"
end

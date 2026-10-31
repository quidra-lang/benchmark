vertices = 'ABCDEFGH'
edges = [
  ['A', 'B', 7], ['C', 'A', 4], ['B', 'C', 9], ['B', 'D', 14], ['D', 'C', 6],
  ['C', 'E', 3], ['E', 'D', 5], ['F', 'D', 11], ['E', 'G', 16], ['G', 'F', 8],
  ['H', 'F', 12], ['G', 'H', 2], ['H', 'E', 10]
]
parent = vertices.chars.to_h { |vertex| [vertex, vertex] }
find = lambda do |vertex|
  while parent[vertex] != vertex
    parent[vertex] = parent[parent[vertex]]
    vertex = parent[vertex]
  end
  vertex
end
accepted = skipped = total = 0
edges.sort_by(&:last).each do |a, b, weight|
  root_a, root_b = find.call(a), find.call(b)
  if root_a == root_b
    skipped += 1
    next
  end
  parent[root_b] = root_a
  accepted += 1
  total += weight
  puts "#{[a, b].sort.join('-')} #{weight}"
  break if accepted == vertices.length - 1
end
puts "total weight: #{total}"
puts "skipped: #{skipped}"

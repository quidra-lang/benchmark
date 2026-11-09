edges = [[5, 0], [3, 8], [7, 2], [1, 6], [0, 2], [5, 3], [7, 5], [6, 4], [8, 7]]
graph = Array.new(9) { [] }
edges.each do |a, b|
  graph[a] << b
  graph[b] << a
end
graph.each(&:sort!)
dfs = lambda do |vertex, seen, order|
  seen.add(vertex)
  order << vertex
  graph[vertex].each { |neighbor| dfs.call(neighbor, seen, order) unless seen.include?(neighbor) }
end
depth = []
dfs.call(0, Set.new, depth)
queue = [0]
seen = Set[0]
breadth = []
until queue.empty?
  vertex = queue.shift
  breadth << vertex
  graph[vertex].each do |neighbor|
    unless seen.include?(neighbor)
      seen.add(neighbor)
      queue << neighbor
    end
  end
end
components = []
seen = Set.new
9.times do |vertex|
  unless seen.include?(vertex)
    component = []
    dfs.call(vertex, seen, component)
    components << component.sort
  end
end
puts "DFS: #{depth.join(' ')}"
puts "BFS: #{breadth.join(' ')}"
puts "components: #{components.length}"
components.each_with_index { |component, i| puts "component #{i + 1}: #{component.join(' ')}" }

module MeshAnalyzer
  module Orientation
    extend self

    def has_directed?(vertices, first, last)
      Topology.directed_edges(vertices).include?([first, last])
    end

    def flip(face)
      a, b, c = face.vertices
      face.vertices = [a, c, b]
    end

    def inconsistent_edges(faces, edges)
      edges.filter_map do |edge, ids|
        next unless ids.length == 2

        a, b = edge
        first = has_directed?(faces[ids[0] - 1].vertices, a, b)
        second = has_directed?(faces[ids[1] - 1].vertices, a, b)
        edge if first == second
      end
    end

    def repair(faces, edges)
      visited = Set.new
      (1..faces.length).each do |seed|
        next unless visited.add?(seed)

        queue = [seed]
        index = 0
        while index < queue.length
          current = queue[index]
          index += 1
          Topology.directed_edges(faces[current - 1].vertices).each do |a, b|
            ids = edges[Topology.key_edge(a, b)]
            next unless ids.length == 2

            other = ids[0] == current ? ids[1] : ids[0]
            next if visited.include?(other)

            flip(faces[other - 1]) if has_directed?(faces[other - 1].vertices, a, b)
            visited.add(other)
            queue << other
          end
        end
      end
    end
  end
end

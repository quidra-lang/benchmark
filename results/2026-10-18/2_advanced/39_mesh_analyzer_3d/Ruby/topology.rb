module MeshAnalyzer
  BoundaryLoop = Struct.new(:number, :component, :vertices, :length, :closed, :kind, :filled,
                            keyword_init: true)

  module Topology
    extend self

    class DisjointSet
      def initialize(size)
        @parent = (0..size).to_a
        @rank = Array.new(size + 1, 0)
      end

      def find(value)
        while @parent[value] != value
          @parent[value] = @parent[@parent[value]]
          value = @parent[value]
        end
        value
      end

      def join(first, second)
        first, second = find(first), find(second)
        return if first == second

        first, second = second, first if @rank[first] < @rank[second]
        @parent[second] = first
        @rank[first] += 1 if @rank[first] == @rank[second]
      end

      def join_faces(ids)
        ids.drop(1).each { |id| join(ids[0], id) }
      end
    end

    def directed_edges(vertices)
      a, b, c = vertices
      [[a, b], [b, c], [c, a]]
    end

    def key_edge(a, b) = a < b ? [a, b] : [b, a]

    def edge_table(faces)
      edges = Hash.new { |hash, edge| hash[edge] = [] }
      faces.each_with_index do |face, index|
        directed_edges(face.vertices).each { |a, b| edges[key_edge(a, b)] << index + 1 }
      end
      edges.sort.to_h
    end

    def analyze(faces)
      edges = edge_table(faces)
      connected = DisjointSet.new(faces.length)
      edges.each_value { |ids| connected.join_faces(ids) }
      groups = (1..faces.length).group_by { |id| connected.find(id) }.values.sort_by(&:first)
      face_components = Array.new(faces.length + 1)
      groups.each_with_index { |ids, index| ids.each { |id| face_components[id] = index + 1 } }
      grouped_edges = edges.keys.group_by { |edge| face_components[edges[edge].first] }
      components = groups.each_with_index.map do |ids, index|
        component_edges = grouped_edges.fetch(index + 1, [])
        { number: index + 1, faces: ids,
          vertices: ids.flat_map { |id| faces[id - 1].vertices }.uniq.sort,
          edges: component_edges,
          boundary: component_edges.select { |edge| edges[edge].length == 1 },
          nonmanifold: component_edges.select { |edge| edges[edge].length >= 3 } }
      end
      incident_faces = Hash.new { |hash, vertex| hash[vertex] = [] }
      faces.each_with_index { |face, index| face.vertices.each { |vertex| incident_faces[vertex] << index + 1 } }
      incident_edges = Hash.new { |hash, vertex| hash[vertex] = [] }
      edges.each { |edge, ids| edge.each { |vertex| incident_edges[vertex] << ids } }
      fans = incident_faces.keys.sort.to_h do |vertex|
        connected = DisjointSet.new(faces.length)
        incident_edges[vertex].each { |ids| connected.join_faces(ids) }
        groups = incident_faces[vertex].group_by { |id| connected.find(id) }.values.sort_by(&:first)
        [vertex, groups]
      end
      components.each do |component|
        component[:nonmanifold_vertices] = component[:vertices].select do |vertex|
          fans[vertex].count { |fan| face_components[fan.first] == component[:number] } >= 2
        end
      end
      { edges: edges, components: components, face_components: face_components, fans: fans,
        nonmanifold_vertices: fans.keys.select { |vertex| fans[vertex].length >= 2 } }
    end

    def trace_loops(mesh)
      loops = []
      mesh[:components].each do |component|
        unused = component[:boundary].to_set
        neighbors = Hash.new { |hash, vertex| hash[vertex] = [] }
        component[:boundary].each do |a, b|
          neighbors[a] << b
          neighbors[b] << a
        end
        neighbors.each_value(&:sort!)
        component[:boundary].each do |edge|
          next unless unused.delete?(edge)

          first, current = edge
          sequence = [first, current]
          while current != first
            other = neighbors[current].find { |vertex| unused.include?(key_edge(current, vertex)) }
            break if other.nil?

            unused.delete(key_edge(current, other))
            sequence << other
            current = other
          end
          closed = sequence.last == first
          sequence.pop if closed
          loops << BoundaryLoop.new(number: loops.length + 1, component: component[:number],
                                    vertices: sequence, length: closed ? sequence.length : sequence.length - 1,
                                    closed: closed, filled: false)
        end
      end
      loops
    end
  end
end

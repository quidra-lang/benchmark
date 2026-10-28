struct EdgeKey: Hashable, Comparable {
    let first: Int
    let second: Int
    var vertices: [Int] { [first, second] }
    var text: String { "\(first) \(second)" }

    init(_ first: Int, _ second: Int) { self.first = min(first, second); self.second = max(first, second) }

    static func < (first: EdgeKey, second: EdgeKey) -> Bool {
        first.first == second.first ? first.second < second.second : first.first < second.first
    }

    func contains(_ vertex: Int) -> Bool { first == vertex || second == vertex }
    func other(_ vertex: Int) -> Int { first == vertex ? second : first }
}

struct ComponentTopology {
    let number: Int
    let faces: [Int]
    let vertices: [Int]
    let edges: [EdgeKey]
    let boundary: [EdgeKey]
    let nonmanifold: [EdgeKey]
    var nonmanifoldVertices: [Int] = []
}

struct MeshTopology {
    let edges: [EdgeKey: [Int]]
    let orderedEdges: [EdgeKey]
    let components: [ComponentTopology]
    let faceComponents: [Int]
    let fans: [Int: [[Int]]]
    let nonmanifoldVertices: [Int]
}

struct BoundaryTrace {
    let component: Int
    let vertices: [Int]
    let closed: Bool
}

func triangleEdges(_ vertices: [Int]) -> [(Int, Int)] {
    [(vertices[0], vertices[1]), (vertices[1], vertices[2]), (vertices[2], vertices[0])]
}

func edgeTable(_ faces: [Face]) -> [EdgeKey: [Int]] {
    var edges: [EdgeKey: [Int]] = [:]
    for (index, face) in faces.enumerated() {
        for (first, second) in triangleEdges(face.vertices) { edges[EdgeKey(first, second), default: []].append(index + 1) }
    }
    return edges
}

func connectedParts(_ members: [Int], _ neighbors: [Int: Set<Int>]) -> [[Int]] {
    var unseen = Set(members)
    var parts: [[Int]] = []
    for seed in members where unseen.contains(seed) {
        unseen.remove(seed)
        var queue = [seed]
        var head = 0
        while head < queue.count {
            let face = queue[head]
            head += 1
            for other in neighbors[face, default: []].sorted() where unseen.contains(other) {
                unseen.remove(other)
                queue.append(other)
            }
        }
        parts.append(queue.sorted())
    }
    return parts
}

func vertexFans(_ vertex: Int, _ faces: [Face], _ edges: [EdgeKey: [Int]]) -> [[Int]] {
    let members = faces.indices.filter { faces[$0].vertices.contains(vertex) }.map { $0 + 1 }
    var neighbors: [Int: Set<Int>] = [:]
    for (edge, participating) in edges where edge.contains(vertex) {
        for first in participating {
            for second in participating where first != second { neighbors[first, default: []].insert(second) }
        }
    }
    return connectedParts(members, neighbors)
}

func analyzeMesh(_ faces: [Face]) -> MeshTopology {
    let edges = edgeTable(faces)
    let orderedEdges = edges.keys.sorted()
    var neighbors: [Int: Set<Int>] = [:]
    for participating in edges.values {
        for first in participating {
            for second in participating where first != second { neighbors[first, default: []].insert(second) }
        }
    }
    let parts = connectedParts(Array(1..<(faces.count + 1)), neighbors)
    var faceComponents = Array(repeating: 0, count: faces.count + 1)
    for (index, part) in parts.enumerated() {
        for face in part { faceComponents[face] = index + 1 }
    }
    let usedVertices = Set(faces.flatMap { $0.vertices }).sorted()
    var fans: [Int: [[Int]]] = [:]
    for vertex in usedVertices { fans[vertex] = vertexFans(vertex, faces, edges) }
    var components: [ComponentTopology] = []
    for (index, part) in parts.enumerated() {
        let number = index + 1
        let vertices = Set(part.flatMap { faces[$0 - 1].vertices }).sorted()
        let componentEdges = orderedEdges.filter { faceComponents[edges[$0]![0]] == number }
        let nonmanifoldVertices = vertices.filter { vertex in
            fans[vertex]!.filter { fan in faceComponents[fan[0]] == number }.count >= 2
        }
        components.append(ComponentTopology(number: number, faces: part, vertices: vertices, edges: componentEdges,
                                             boundary: componentEdges.filter { edges[$0]!.count == 1 },
                                             nonmanifold: componentEdges.filter { edges[$0]!.count >= 3 },
                                             nonmanifoldVertices: nonmanifoldVertices))
    }
    return MeshTopology(edges: edges, orderedEdges: orderedEdges, components: components,
                         faceComponents: faceComponents, fans: fans,
                         nonmanifoldVertices: usedVertices.filter { fans[$0]!.count >= 2 })
}

func boundaryTraces(_ mesh: MeshTopology) -> [BoundaryTrace] {
    var traces: [BoundaryTrace] = []
    for component in mesh.components {
        var unused = Set(component.boundary)
        for edge in component.boundary where unused.contains(edge) {
            unused.remove(edge)
            var sequence = edge.vertices
            var current = edge.second
            while current != edge.first {
                guard let chosen = unused.filter({ $0.contains(current) }).min(by: { $0.other(current) < $1.other(current) }) else { break }
                unused.remove(chosen)
                current = chosen.other(current)
                sequence.append(current)
            }
            let closed = current == edge.first
            if closed { sequence.removeLast() }
            traces.append(BoundaryTrace(component: component.number, vertices: sequence, closed: closed))
        }
    }
    return traces
}

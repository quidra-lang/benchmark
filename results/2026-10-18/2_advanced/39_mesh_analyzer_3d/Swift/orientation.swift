func hasDirected(_ vertices: [Int], _ start: Int, _ end: Int) -> Bool {
    triangleEdges(vertices).contains { $0.0 == start && $0.1 == end }
}

func flip(_ face: inout Face) { face.vertices.swapAt(1, 2) }

func inconsistentEdges(_ faces: [Face], _ edges: [EdgeKey: [Int]]) -> [EdgeKey] {
    edges.keys.sorted().filter { edge in
        let adjacent = edges[edge]!
        return adjacent.count == 2
            && hasDirected(faces[adjacent[0] - 1].vertices, edge.first, edge.second)
                == hasDirected(faces[adjacent[1] - 1].vertices, edge.first, edge.second)
    }
}

func repairOrientation(_ faces: inout [Face], _ edges: [EdgeKey: [Int]]) {
    var visited: Set<Int> = []
    for seed in 1..<(faces.count + 1) where !visited.contains(seed) {
        visited.insert(seed)
        var queue = [seed]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            for (start, end) in triangleEdges(faces[current - 1].vertices) {
                let adjacent = edges[EdgeKey(start, end)]!
                if adjacent.count != 2 { continue }
                let other = adjacent[0] == current ? adjacent[1] : adjacent[0]
                if visited.contains(other) { continue }
                if hasDirected(faces[other - 1].vertices, start, end) { flip(&faces[other - 1]) }
                visited.insert(other)
                queue.append(other)
            }
        }
    }
}

func orientableComponents(_ faces: [Face], _ mesh: MeshTopology) -> [Int: Bool] {
    var copied = faces
    repairOrientation(&copied, mesh.edges)
    let violations = Set(inconsistentEdges(copied, mesh.edges))
    return Dictionary(uniqueKeysWithValues: mesh.components.map { component in
        (component.number, !component.edges.contains { violations.contains($0) })
    })
}

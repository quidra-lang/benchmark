struct SnappedVertex {
    let number: Int
    let before: Vector3
    let after: Vector3
}

struct RemovedTriangle {
    let face: Face
    let reason: String
}

func floorDivide(_ value: Int, _ divisor: Int) -> Int { value / divisor - (value % divisor < 0 ? 1 : 0) }

func splitPolygons(_ polygons: [Polygon]) -> [Face] {
    var triangles: [Face] = []
    for polygon in polygons {
        for index in 1..<(polygon.vertices.count - 1) {
            triangles.append(Face(triangle: triangles.count + 1, polygon: polygon.number, line: polygon.line,
                                  group: polygon.group, vertices: [polygon.vertices[0], polygon.vertices[index], polygon.vertices[index + 1]]))
        }
    }
    return triangles
}

func snappedVertices(_ vertices: [Vector3], _ spacing: Int) -> (points: [Vector3], changes: [SnappedVertex]) {
    var points: [Vector3] = [.zero]
    var changes: [SnappedVertex] = []
    for number in 1..<vertices.count {
        let coordinates = vertices[number].coordinates.map { spacing * floorDivide(2 * $0 + spacing, 2 * spacing) }
        let point = Vector3(x: coordinates[0], y: coordinates[1], z: coordinates[2])
        points.append(point)
        if point != vertices[number] { changes.append(SnappedVertex(number: number, before: vertices[number], after: point)) }
    }
    return (points, changes)
}

func representatives(_ points: [Vector3], merge: Bool) -> [Int] {
    var owners: [Vector3: Int] = [:]
    var result = [0]
    for number in 1..<points.count {
        if !merge { result.append(number) }
        else {
            if owners[points[number]] == nil { owners[points[number]] = number }
            result.append(owners[points[number]]!)
        }
    }
    return result
}

func cleanedFaces(_ triangles: [Face], _ points: [Vector3], _ representatives: [Int],
                  removeZero: Bool, removeDuplicate: Bool) -> (faces: [Face], removed: [RemovedTriangle]) {
    var faces: [Face] = []
    var removed: [RemovedTriangle] = []
    var seen: Set<[Int]> = []
    for triangle in triangles {
        var face = triangle
        face.vertices = triangle.vertices.map { representatives[$0] }
        var reason: String?
        if Set(face.vertices).count < 3 { reason = "repeated" }
        else if removeZero && normal(face, points) == .zero { reason = "zero_area" }
        if reason == nil {
            let identifier = face.vertices.sorted()
            if removeDuplicate && seen.contains(identifier) { reason = "duplicate" }
            else { seen.insert(identifier) }
        }
        if let reason { removed.append(RemovedTriangle(face: triangle, reason: reason)) }
        else { faces.append(face) }
    }
    return (faces, removed)
}

func remapVertices(_ points: [Vector3], _ representatives: [Int], _ faces: [Face], keepUnused: Bool)
    -> (points: [Vector3], faces: [Face], numbers: [Int: Int]) {
    let present = keepUnused ? (1..<points.count).filter { representatives[$0] == $0 }
        : Set(faces.flatMap { $0.vertices }).sorted()
    var numbers: [Int: Int] = [:]
    for (index, number) in present.enumerated() { numbers[number] = index + 1 }
    let mapped = faces.map { face -> Face in
        var result = face
        result.vertices = face.vertices.map { numbers[$0]! }
        return result
    }
    return ([.zero] + present.map { points[$0] }, mapped, numbers)
}

func holeTriangles(_ vertices: [Int]) -> [Face] {
    (2..<vertices.count).map { index in
        Face(triangle: nil, polygon: nil, line: nil, group: "fill", vertices: [vertices[0], vertices[index], vertices[index - 1]])
    }
}

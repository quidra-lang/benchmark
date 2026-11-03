import Foundation

struct Vector3: Hashable {
    let x: Int
    let y: Int
    let z: Int
    static let zero = Vector3(x: 0, y: 0, z: 0)
    var coordinates: [Int] { [x, y, z] }
    var text: String { "\(x) \(y) \(z)" }
}

func subtract(_ first: Vector3, _ second: Vector3) -> Vector3 {
    Vector3(x: first.x - second.x, y: first.y - second.y, z: first.z - second.z)
}

func add(_ first: Vector3, _ second: Vector3) -> Vector3 {
    Vector3(x: first.x + second.x, y: first.y + second.y, z: first.z + second.z)
}

func cross(_ first: Vector3, _ second: Vector3) -> Vector3 {
    Vector3(x: first.y * second.z - first.z * second.y,
            y: first.z * second.x - first.x * second.z,
            z: first.x * second.y - first.y * second.x)
}

func dot(_ first: Vector3, _ second: Vector3) -> Int { first.x * second.x + first.y * second.y + first.z * second.z }

func normal(_ face: Face, _ points: [Vector3]) -> Vector3 {
    let vertices = face.vertices.map { points[$0] }
    return cross(subtract(vertices[1], vertices[0]), subtract(vertices[2], vertices[0]))
}

func determinant(_ face: Face, _ points: [Vector3]) -> Int {
    dot(points[face.vertices[0]], cross(points[face.vertices[1]], points[face.vertices[2]]))
}

func area(_ faces: [Face], _ points: [Vector3]) -> Double {
    var total = 0.0
    for face in faces {
        let vector = normal(face, points)
        total += sqrt(Double(dot(vector, vector)))
    }
    return total / 2
}

func triangleAngle(_ face: Face, _ points: [Vector3]) -> String {
    let a = points[face.vertices[0]]
    let b = points[face.vertices[1]]
    let c = points[face.vertices[2]]
    let minimum = min(dot(subtract(b, a), subtract(c, a)),
                      min(dot(subtract(c, b), subtract(a, b)), dot(subtract(a, c), subtract(b, c))))
    return minimum < 0 ? "obtuse" : minimum == 0 ? "right" : "acute"
}

func edgeLengthSquared(_ edge: EdgeKey, _ points: [Vector3]) -> Int {
    let difference = subtract(points[edge.first], points[edge.second])
    return dot(difference, difference)
}

func windingNumber(_ faceIDs: [Int], _ faces: [Face], _ points: [Vector3], _ sample: Vector3) -> Int {
    var total = 0.0
    for faceID in faceIDs {
        let vertices = faces[faceID - 1].vertices.map { subtract(points[$0], sample) }
        let a = vertices[0]
        let b = vertices[1]
        let c = vertices[2]
        let la = sqrt(Double(dot(a, a)))
        let lb = sqrt(Double(dot(b, b)))
        let lc = sqrt(Double(dot(c, c)))
        let denominator = la * lb * lc + Double(dot(a, b)) * lc
            + Double(dot(b, c)) * la + Double(dot(c, a)) * lb
        total += 2 * atan2(Double(dot(a, cross(b, c))), denominator)
    }
    return Int((total / (4 * 3.141592653589793)).rounded())
}

func volume6(_ faceIDs: [Int], _ faces: [Face], _ points: [Vector3]) -> Int {
    faceIDs.reduce(0) { $0 + determinant(faces[$1 - 1], points) }
}

func greatestCommonDivisor(_ first: Int, _ second: Int) -> Int {
    var a = abs(first)
    var b = abs(second)
    while b != 0 { (a, b) = (b, a % b) }
    return a
}

func fraction(_ numerator: Int, _ denominator: Int) -> String {
    let divisor = greatestCommonDivisor(numerator, denominator)
    let signed = denominator < 0 ? -1 : 1
    let top = signed * numerator / divisor
    let bottom = abs(denominator) / divisor
    return bottom == 1 ? String(top) : "\(top)/\(bottom)"
}

func centroid(_ faceIDs: [Int], _ faces: [Face], _ points: [Vector3], _ sixVolume: Int) -> [String] {
    (0..<3).map { axis in
        var numerator = 0
        for faceID in faceIDs {
            let face = faces[faceID - 1]
            let total = face.vertices.reduce(0) { $0 + points[$1].coordinates[axis] }
            numerator += determinant(face, points) * total
        }
        return fraction(numerator, 4 * sixVolume)
    }
}

func real(_ value: Double) -> String {
    String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value == 0 ? 0.0 : value)
}

func boundingBox(_ vertices: [Int], _ points: [Vector3]) -> [Int] {
    let coordinates = vertices.map { points[$0].coordinates }
    return (0..<3).map { axis in coordinates.map { $0[axis] }.min()! }
        + (0..<3).map { axis in coordinates.map { $0[axis] }.max()! }
}

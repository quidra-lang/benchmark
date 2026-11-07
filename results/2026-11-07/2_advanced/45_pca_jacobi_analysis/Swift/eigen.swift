import Foundation

struct EigenSystem {
    let values: [Double]
    let vectors: Matrix
    let sweeps: Int
}

struct PowerComponent {
    let value: Double
    let vector: [Double]
    let agreement: Int?
}

func offDiagonal(_ matrix: Matrix) -> Double {
    var total = 0.0
    for p in 0..<(matrix.count - 1) {
        for q in (p + 1)..<matrix.count { total = total + matrix[p][q] * matrix[p][q] }
    }
    return total
}

func rotate(_ matrix: inout Matrix, _ vectors: inout Matrix, _ p: Int, _ q: Int) {
    if matrix[p][q] == 0 { return }
    let theta = (matrix[q][q] - matrix[p][p]) / (2 * matrix[p][q])
    var t = 1 / (abs(theta) + sqrt(theta * theta + 1))
    if theta < 0 { t = -t }
    let c = 1 / sqrt(t * t + 1), s = t * c
    for r in matrix.indices where r != p && r != q {
        let arp = matrix[r][p], arq = matrix[r][q]
        let first = c * arp - s * arq, second = s * arp + c * arq
        matrix[r][p] = first
        matrix[p][r] = first
        matrix[r][q] = second
        matrix[q][r] = second
    }
    let apq = matrix[p][q]
    matrix[p][p] = matrix[p][p] - t * apq
    matrix[q][q] = matrix[q][q] + t * apq
    matrix[p][q] = 0
    matrix[q][p] = 0
    for r in vectors.indices {
        let vrp = vectors[r][p], vrq = vectors[r][q]
        vectors[r][p] = c * vrp - s * vrq
        vectors[r][q] = s * vrp + c * vrq
    }
}

func jacobi(_ matrix: Matrix) -> EigenSystem {
    var work = matrix, vectors = identity(matrix.count)
    let initial = offDiagonal(work)
    var sweeps = 0
    if initial > 0 {
        for number in 1...100 {
            for p in 0..<(matrix.count - 1) {
                for q in (p + 1)..<matrix.count { rotate(&work, &vectors, p, q) }
            }
            let remaining = offDiagonal(work)
            if sweeps == 0 && remaining < 1e-16 * initial { sweeps = number }
            if remaining < 1e-22 * initial { break }
        }
    }
    let order = matrix.indices.sorted { work[$0][$0] == work[$1][$1] ? $0 < $1 : work[$0][$0] > work[$1][$1] }
    return EigenSystem(values: order.map { work[$0][$0] }, vectors: order.map { orient(normalize(column(vectors, $0))) }, sweeps: sweeps)
}

func powerIteration(_ matrix: Matrix, _ references: Matrix) -> [PowerComponent] {
    var work = matrix
    var components: [PowerComponent] = []
    for reference in references {
        let opposite = reference.map { -$0 }
        var x = Array(repeating: 1.0, count: matrix.count)
        var agreement: Int?
        for step in 1...1000 {
            x = normalize(multiply(work, x))
            let difference = min(maxDifference(x, reference), maxDifference(x, opposite))
            if agreement == nil && difference < 0.000001 { agreement = step }
        }
        let value = dot(x, multiply(work, x)), vector = orient(normalize(x))
        deflate(&work, value, vector)
        components.append(PowerComponent(value: value, vector: vector, agreement: agreement))
    }
    return components
}

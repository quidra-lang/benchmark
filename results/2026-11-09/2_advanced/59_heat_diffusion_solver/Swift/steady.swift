import Foundation

enum SolverMethod: String, CaseIterable { case jacobi, gaussSeidel = "gauss_seidel", sor, estimated = "sor_estimated" }
struct IterationResult { let method: SolverMethod; let field: [Double]; let changes: [Double]; let omega: Double; let converged: Bool; var count: Int { changes.count }; var rate: Double { sqrt(changes[count - 1] / changes[count - 3]) } }
func gValue(_ system: PlateSystem, _ field: [Double], _ point: Int) -> Double {
    let terms = system.faces[point].compactMap { face -> Double? in if let neighbor = face.neighbor { return face.conductance * field[neighbor] }; if let theta = face.temperature { return face.conductance * theta }; return nil }
    return orderedSum(terms) + system.sourceAll[point]
}
func iterate(_ system: PlateSystem, _ initial: Double, _ tolerance: Double, _ maximum: Int, _ method: SolverMethod, _ omega: Double = 1) -> IterationResult {
    var field = Array(repeating: initial, count: system.mesh.count), changes: [Double] = []
    for _ in 0..<maximum {
        let previous = field
        if method == .jacobi { field = field.indices.map { gValue(system, previous, $0) / system.diagonal[$0] } }
        else { for point in field.indices { let value = gValue(system, field, point) / system.diagonal[point]; field[point] = method == .gaussSeidel ? value : field[point] + omega * (value - field[point]) } }
        let change = field.indices.map { abs(field[$0] - previous[$0]) }.max()!
        changes.append(change); if change < tolerance { break }
    }
    return IterationResult(method: method, field: field, changes: changes, omega: omega, converged: changes.last! < tolerance)
}
func bandSolve(_ system: PlateSystem, _ rightSides: [[Double]]) -> [[Double]] {
    let count = system.mesh.count, width = system.mesh.width
    var matrix = Array(repeating: Array(repeating: 0.0, count: count), count: count), vectors = rightSides
    for point in 0..<count { matrix[point][point] = system.diagonal[point]; for face in system.faces[point] { if let neighbor = face.neighbor { matrix[point][neighbor] = -face.conductance } } }
    for column in 0..<count {
        let stop = min(count, column + width + 1)
        for row in (column + 1)..<stop {
            let factor = matrix[row][column] / matrix[column][column]
            matrix[row][column] = 0
            for next in (column + 1)..<stop { let pivot = matrix[column][next]; matrix[row][next] -= factor * pivot }
            for i in vectors.indices { let pivot = vectors[i][column]; vectors[i][row] -= factor * pivot }
        }
    }
    return vectors.map { values in
        var field = Array(repeating: 0.0, count: count)
        for row in (0..<count).reversed() { var value = values[row]; for column in (row + 1)..<min(count, row + width + 1) { value -= matrix[row][column] * field[column] }; field[row] = value / matrix[row][row] }
        return field
    }
}
func maximumResidual(_ system: PlateSystem, _ field: [Double], _ rhs: [Double]) -> Double {
    var maximum = 0.0
    for point in field.indices { var residual = rhs[point]; for face in system.faces[point] { if let neighbor = face.neighbor { residual += face.conductance * field[neighbor] } }; residual -= system.diagonal[point] * field[point]; maximum = max(maximum, abs(residual)) }
    return maximum
}

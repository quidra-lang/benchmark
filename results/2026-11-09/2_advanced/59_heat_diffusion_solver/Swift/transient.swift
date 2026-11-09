import Foundation

func orderedSum<S: Sequence>(_ values: S) -> Double where S.Element == Double { var iterator = values.makeIterator(), sum = iterator.next() ?? 0; while let value = iterator.next() { sum += value }; return sum }
func heatFlow(_ system: PlateSystem, _ field: [Double], _ point: Int, _ directions: [Int]) -> Double {
    let terms = directions.compactMap { direction -> Double? in
        let face = system.faces[point][direction]
        if let neighbor = face.neighbor { return face.conductance * (field[neighbor] - field[point]) }
        if let theta = face.temperature { return face.conductance * (theta - field[point]) }
        return nil
    }
    return orderedSum(terms)
}
func horizontalFlow(_ system: PlateSystem, _ field: [Double], _ point: Int) -> Double { heatFlow(system, field, point, [0, 1]) }
func verticalFlow(_ system: PlateSystem, _ field: [Double], _ point: Int) -> Double { heatFlow(system, field, point, [2, 3]) }
func totalFlow(_ system: PlateSystem, _ field: [Double], _ point: Int) -> Double { heatFlow(system, field, point, [0, 1, 2, 3]) }
func thomas(_ lower: [Double], _ diagonal: [Double], _ upper: [Double], _ rhs: [Double]) -> [Double] {
    let count = diagonal.count
    var upperPrime = [upper[0] / diagonal[0]], rhsPrime = [rhs[0] / diagonal[0]]
    for i in 1..<count { let pivot = diagonal[i] - lower[i] * upperPrime[i - 1]; upperPrime.append(upper[i] / pivot); rhsPrime.append((rhs[i] - lower[i] * rhsPrime[i - 1]) / pivot) }
    var result = Array(repeating: 0.0, count: count)
    result[count - 1] = rhsPrime[count - 1]
    for i in (0..<(count - 1)).reversed() { let following = result[i + 1]; result[i] = rhsPrime[i] - upperPrime[i] * following }
    return result
}
func sweep(_ system: PlateSystem, _ tau: Double, _ rhs: [Double], horizontal: Bool) -> [Double] {
    let mesh = system.mesh, count = horizontal ? mesh.height : mesh.width, length = horizontal ? mesh.width : mesh.height, firstFace = horizontal ? 0 : 2, secondFace = horizontal ? 1 : 3
    var field = Array(repeating: 0.0, count: mesh.count)
    for line in 0..<count {
        let cells = (0..<length).map { horizontal ? mesh.cell(line, $0) : mesh.cell($0, line) }
        var lower: [Double] = [], diagonal: [Double] = [], upper: [Double] = [], values: [Double] = []
        for point in cells {
            let first = system.faces[point][firstFace], second = system.faces[point][secondFace]
            lower.append(first.neighbor == nil ? 0 : -first.conductance); diagonal.append(system.capacity[point] / tau + first.conductance + second.conductance); upper.append(second.neighbor == nil ? 0 : -second.conductance)
            var value = rhs[point]
            if let theta = first.temperature { value += first.conductance * theta }; if let theta = second.temperature { value += second.conductance * theta }; values.append(value)
        }
        let solved = thomas(lower, diagonal, upper, values)
        for (i, point) in cells.enumerated() { field[point] = solved[i] }
    }
    return field
}
func advance(_ method: TransientMethod, _ system: PlateSystem, _ field: [Double], _ source: [Double], _ dt: Double) -> (field: [Double], intermediate: [Double]?) {
    let points = 0..<system.mesh.count
    if method == .ftcs { return (points.map { field[$0] + dt * (totalFlow(system, field, $0) + source[$0]) / system.capacity[$0] }, nil) }
    let tau = method == .backward ? dt : dt / 2, vertical = points.map { verticalFlow(system, field, $0) }
    let rhs = points.map { system.capacity[$0] / tau * field[$0] + vertical[$0] + source[$0] }, intermediate = sweep(system, tau, rhs, horizontal: true)
    let second = points.map { p in method == .backward ? system.capacity[p] / tau * intermediate[p] - vertical[p] : system.capacity[p] / tau * intermediate[p] + horizontalFlow(system, intermediate, p) + source[p] }
    return (sweep(system, tau, second, horizontal: false), intermediate)
}

import Foundation

let pi = 3.141592653589793
typealias Matrix = [[Double]]
func orderedSum<S: Sequence>(_ values: S) -> Double where S.Element == Double { var total = 0.0; for value in values { total = total + value }; return total }

struct Solution {
    var x: Double
    var y: Double
    var z: Double
    var origin: Double
}
struct Observation { let station: Station; let time: Double }
struct Iteration { let number: Int; let solution: Solution; let rms: Double }
struct GridResult { let solution: Solution; let rms: Double; let profile: [Double] }
struct Refinement { let solution: Solution; let trace: [Iteration]; let residuals: [Double]; let rms: Double }
struct LocationRun { let grid: GridResult; let refined: Refinement }

func distance(_ solution: Solution, _ station: Station) -> Double {
    let dx = solution.x - Double(station.x), dy = solution.y - Double(station.y), dz = solution.z + Double(station.elevation)
    return sqrt(dx * dx + dy * dy + dz * dz)
}
func residuals(_ solution: Solution, _ observations: [Observation], _ velocity: Double) -> [Double] { observations.map { $0.time - solution.origin - distance(solution, $0.station) / velocity } }
func rms(_ solution: Solution, _ observations: [Observation], _ velocity: Double) -> Double { sqrt(orderedSum(residuals(solution, observations, velocity).map { $0 * $0 }) / Double(observations.count)) }

func gridSearch(_ observations: [Observation], _ params: Parameters) -> GridResult {
    var best: Solution?, bestError = Double.infinity, profile: [Int: Double] = [:]
    for x in params.gridX.values {
        for y in params.gridY.values {
            for z in params.gridZ.values {
                let point = Solution(x: Double(x), y: Double(y), z: Double(z), origin: 0)
                let travel = observations.map { $0.time - distance(point, $0.station) / params.velocity }
                let origin = orderedSum(travel) / Double(travel.count)
                let error = orderedSum(travel.map { ($0 - origin) * ($0 - origin) })
                if error < bestError { best = Solution(x: point.x, y: point.y, z: point.z, origin: origin); bestError = error }
                if profile[z] == nil || error < profile[z]! { profile[z] = error }
            }
        }
    }
    return GridResult(solution: best!, rms: sqrt(bestError / Double(observations.count)), profile: params.gridZ.values.map { sqrt(profile[$0]! / Double(observations.count)) })
}

func cholesky(_ matrix: Matrix) -> Matrix {
    let size = matrix.count
    var lower = Array(repeating: Array(repeating: 0.0, count: size), count: size)
    for row in 0..<size {
        for column in 0...row {
            let total = orderedSum((0..<column).map { lower[row][$0] * lower[column][$0] })
            let remainder = matrix[row][column] - total
            lower[row][column] = row == column ? sqrt(remainder) : remainder / lower[column][column]
        }
    }
    return lower
}

func choleskySolve(_ lower: Matrix, _ right: [Double]) -> [Double] {
    let size = lower.count
    var forward = Array(repeating: 0.0, count: size), solution = Array(repeating: 0.0, count: size)
    for row in 0..<size {
        let total = orderedSum((0..<row).map { lower[row][$0] * forward[$0] })
        forward[row] = (right[row] - total) / lower[row][row]
    }
    for row in (0..<size).reversed() {
        let total = orderedSum(((row + 1)..<size).map { lower[$0][row] * solution[$0] })
        solution[row] = (forward[row] - total) / lower[row][row]
    }
    return solution
}

func normals(_ solution: Solution, _ observations: [Observation], _ velocity: Double) -> (matrix: Matrix, right: [Double]) {
    var matrix = Array(repeating: Array(repeating: 0.0, count: 4), count: 4), right = Array(repeating: 0.0, count: 4)
    let errors = residuals(solution, observations, velocity)
    for (index, observation) in observations.enumerated() {
        let station = observation.station, d = distance(solution, observation.station)
        let g = [(solution.x - Double(station.x)) / (velocity * d), (solution.y - Double(station.y)) / (velocity * d), (solution.z + Double(station.elevation)) / (velocity * d), 1]
        for a in 0..<4 {
            right[a] = right[a] + g[a] * errors[index]
            for c in 0..<4 { matrix[a][c] = matrix[a][c] + g[a] * g[c] }
        }
    }
    return (matrix, right)
}

func geiger(_ initial: Solution, _ observations: [Observation], _ velocity: Double) -> Refinement {
    var solution = initial, trace: [Iteration] = []
    for iteration in 1...8 {
        let normal = normals(solution, observations, velocity), delta = choleskySolve(cholesky(normal.matrix), normal.right)
        solution.x = solution.x + delta[0]; solution.y = solution.y + delta[1]; solution.z = solution.z + delta[2]; solution.origin = solution.origin + delta[3]
        if solution.z < 0 { solution.z = 0 }
        trace.append(Iteration(number: iteration, solution: solution, rms: rms(solution, observations, velocity)))
    }
    return Refinement(solution: solution, trace: trace, residuals: residuals(solution, observations, velocity), rms: rms(solution, observations, velocity))
}

func runLocation(_ observations: [Observation], _ params: Parameters) -> LocationRun {
    let grid = gridSearch(observations, params)
    return LocationRun(grid: grid, refined: geiger(grid.solution, observations, params.velocity))
}

struct Ellipse { let semiMajor: Double; let semiMinor: Double; let azimuth: Double; let depthError: Double; let timeError: Double }

func errorEllipse(_ solution: Solution, _ observations: [Observation], _ velocity: Double) -> Ellipse {
    let lower = cholesky(normals(solution, observations, velocity).matrix)
    let columns = (0..<4).map { c in choleskySolve(lower, (0..<4).map { $0 == c ? 1 : 0 }) }
    let variance = orderedSum(residuals(solution, observations, velocity).map { $0 * $0 }) / Double(observations.count - 4)
    let covariance = (0..<4).map { row in (0..<4).map { variance * columns[$0][row] } }
    let xx = covariance[0][0], yy = covariance[1][1], xy = covariance[0][1]
    let midpoint = (xx + yy) / 2, halfDifference = (xx - yy) / 2, radius = sqrt(halfDifference * halfDifference + xy * xy)
    let theta = atan2(2 * xy, xx - yy) / 2 * 180 / pi
    var azimuth = 90 - theta
    if azimuth >= 180 { azimuth -= 180 }
    if azimuth < 0 { azimuth += 180 }
    return Ellipse(semiMajor: sqrt(midpoint + radius), semiMinor: sqrt(midpoint - radius), azimuth: azimuth, depthError: sqrt(covariance[2][2]), timeError: sqrt(covariance[3][3]))
}

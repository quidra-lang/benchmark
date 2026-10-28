import Foundation

struct PassRecord { let full: Bool; let examined: Int; let changed: Int; let alpha: [Double]? }
final class Model {
    let points: [Point]
    let labels: [Int]
    let kernel: Kernel
    let matrix: [[Double]]
    let coefficient: Double
    let tolerance: Double
    let epsilon: Double
    let maximumPasses: Int
    var alpha: [Double]
    var b = 0.0
    var errors: [Double]
    var fullPasses = 0
    var nonboundPasses = 0
    var examined = 0
    var steps = 0
    var choices = [0, 0, 0]
    var clipping = [0, 0, 0]
    var records: [PassRecord] = []
    var converged = false
    var passes: Int { fullPasses + nonboundPasses }
    init(_ points: [Point], _ labels: [Int], _ kernel: Kernel, _ matrix: [[Double]], _ coefficient: Double, _ settings: Settings) {
        self.points = points; self.labels = labels; self.kernel = kernel; self.matrix = matrix; self.coefficient = coefficient; tolerance = settings.tolerance; epsilon = settings.epsilon; maximumPasses = settings.maximumPasses; alpha = Array(repeating: 0, count: points.count); errors = labels.map { -Double($0) }
    }
    func nonbound(_ index: Int) -> Bool { alpha[index] > 0 && alpha[index] < coefficient }
    func snap(_ value: Double) -> Double { value < 0.00000001 ? 0 : value > coefficient - 0.00000001 ? coefficient : value }
    func take(_ first: Int, _ second: Int) -> Bool {
        if first == second { return false }
        let alpha1 = alpha[first], alpha2 = alpha[second], y1 = Double(labels[first]), y2 = Double(labels[second]), error1 = errors[first], error2 = errors[second]
        let lower = y1 != y2 ? max(0, alpha2 - alpha1) : max(0, alpha2 + alpha1 - coefficient), upper = y1 != y2 ? min(coefficient, coefficient + alpha2 - alpha1) : min(coefficient, alpha2 + alpha1)
        if lower == upper { return false }
        let k11 = matrix[first][first], k12 = matrix[first][second], k22 = matrix[second][second], eta = k11 + k22 - 2 * k12
        if eta <= 0 { return false }
        var a2 = alpha2 + y2 * (error1 - error2) / eta, clip = 0
        if a2 < lower { a2 = lower; clip = 1 } else if a2 > upper { a2 = upper; clip = 2 }
        a2 = snap(a2)
        if abs(a2 - alpha2) < epsilon * (a2 + alpha2 + epsilon) { return false }
        let a1 = snap(alpha1 + y1 * y2 * (alpha2 - a2)), t1 = y1 * (a1 - alpha1), t2 = y2 * (a2 - alpha2)
        let b1 = error1 + t1 * k11 + t2 * k12 + b, b2 = error2 + t1 * k12 + t2 * k22 + b, threshold = a1 > 0 && a1 < coefficient ? b1 : a2 > 0 && a2 < coefficient ? b2 : (b1 + b2) / 2, delta = threshold - b
        for i in points.indices { errors[i] = errors[i] + (t1 * matrix[first][i] + t2 * matrix[second][i] - delta) }
        if a1 > 0 && a1 < coefficient { errors[first] = 0 }; if a2 > 0 && a2 < coefficient { errors[second] = 0 }
        alpha[first] = a1; alpha[second] = a2; b = threshold; steps += 1; clipping[clip] += 1
        return true
    }
    func examine(_ second: Int) -> Int {
        examined += 1
        let residual = errors[second] * Double(labels[second]), violates = (residual < -tolerance && alpha[second] < coefficient) || (residual > tolerance && alpha[second] > 0)
        if !violates { return 0 }
        var partner: Int?, difference = -1.0
        for i in points.indices where i != second && nonbound(i) { let value = abs(errors[i] - errors[second]); if value > difference { difference = value; partner = i } }
        if let partner, take(partner, second) { choices[0] += 1; return 1 }
        for first in points.indices { if nonbound(first) && take(first, second) { choices[1] += 1; return 1 } }
        for first in points.indices { if take(first, second) { choices[2] += 1; return 1 } }
        return 0
    }
    func fit() {
        var all = true
        while true {
            let before = examined
            var changed = 0
            for i in points.indices { if all || nonbound(i) { changed += examine(i) } }
            if all { fullPasses += 1 } else { nonboundPasses += 1 }
            records.append(PassRecord(full: all, examined: examined - before, changed: changed, alpha: all ? alpha : nil))
            if all && changed == 0 { converged = true; break }
            if passes == maximumPasses { break }
            if all { all = false } else if changed == 0 { all = true }
        }
    }
    func decision(_ point: Point) -> Double { var total = 0.0; for i in alpha.indices where alpha[i] > 0 { total += alpha[i] * Double(labels[i]) * kernel.value(points[i], point) }; return total - b }
    func trainingDecisions() -> [Double] { matrix.map { row in var total = 0.0; for i in alpha.indices where alpha[i] > 0 { total += alpha[i] * Double(labels[i]) * row[i] }; return total - b } }
}
func train(_ points: [Point], _ labels: [Int], _ kernel: Kernel, _ matrix: [[Double]], _ coefficient: Double, _ settings: Settings) -> Model { let model = Model(points, labels, kernel, matrix, coefficient, settings); model.fit(); return model }

import Foundation

enum KernelKind { case linear, polynomial(Int, Double, Double), rbf(Double) }
struct Kernel {
    let name: String
    let kind: KernelKind
    var isLinear: Bool { if case .linear = kind { return true }; return false }
    func value(_ first: Point, _ second: Point) -> Double {
        if case .rbf(let gamma) = kind { let e1 = first.x - second.x, e2 = first.y - second.y; return exp(-gamma * (e1 * e1 + e2 * e2)) }
        let product = first.x * second.x + first.y * second.y
        if case .polynomial(let degree, let gamma, let constant) = kind { let factor = gamma * product + constant; var result = 1.0; for _ in 0..<degree { result *= factor }; return result }
        return product
    }
    var description: String { switch kind { case .linear: return "linear"; case .polynomial(let degree, let gamma, let constant): return "poly degree \(degree) gamma \(fixed(gamma)) coef0 \(fixed(constant))"; case .rbf(let gamma): return "rbf gamma \(fixed(gamma))" } }
    func matrix(_ points: [Point]) -> [[Double]] { points.map { first in points.map { value(first, $0) } } }
}
func submatrix(_ matrix: [[Double]], _ indices: [Int]) -> [[Double]] { indices.map { i in indices.map { matrix[i][$0] } } }

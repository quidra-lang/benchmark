import Foundation

final class Minstd {
    private var state: Int64
    private(set) var draws = 0
    init(_ seed: Int64) { state = seed }
    func draw() -> Int64 { state = 48271 * state % 2147483647; draws += 1; return state }
    func between(_ minimum: Int, _ maximum: Int) -> Int { minimum + Int(draw() % Int64(maximum - minimum + 1)) }
}

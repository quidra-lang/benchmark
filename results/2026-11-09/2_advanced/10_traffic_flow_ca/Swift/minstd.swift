final class Minstd {
    var state: Int
    init(_ seed: Int) { state = seed }
    func draw() -> Int { state = state * 48271 % 2147483647; return state }
}
func select(_ weights: [Int], _ random: Int) -> Int {
    let value = random % weights.reduce(0, +)
    var total = 0
    for (index, weight) in weights.enumerated() { total += weight; if value < total { return index } }
    return weights.count - 1
}

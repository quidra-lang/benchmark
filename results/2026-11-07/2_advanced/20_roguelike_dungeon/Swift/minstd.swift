final class Minstd {
    var state: Int
    init(_ state: Int) { self.state = state }
    @discardableResult func draw() -> Int { state = state * 48271 % 2147483647; return state }
    func rnd(_ size: Int) -> Int { draw() % size }
    func roll(_ count: Int, _ sides: Int) -> Int {
        var total = 0
        for _ in 0..<count { total += 1 + rnd(sides) }
        return total
    }
    func select(_ weights: [Int]) -> Int {
        let threshold = rnd(weights.reduce(0, +))
        var total = 0
        for (index, weight) in weights.enumerated() { total += weight; if threshold < total { return index } }
        preconditionFailure()
    }
}

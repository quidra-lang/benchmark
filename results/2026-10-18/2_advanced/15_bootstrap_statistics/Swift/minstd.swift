struct Minstd {
    var state: Int64

    mutating func draw() -> Int64 {
        state = 48271 * state % 2147483647
        return state
    }

    mutating func drawBelow(_ limit: Int) -> Int {
        Int(draw() % Int64(limit))
    }

    mutating func shuffle<T>(_ items: inout [T]) {
        guard items.count >= 2 else { return }
        for index in stride(from: items.count - 1, through: 1, by: -1) {
            let other = drawBelow(index + 1)
            items.swapAt(index, other)
        }
    }
}

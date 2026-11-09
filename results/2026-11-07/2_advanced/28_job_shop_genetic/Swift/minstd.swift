struct Minstd {
    var state: Int
    mutating func draw() -> Int {
        state = state*48271%2147483647;
        return state
    }
    mutating func below(_ m: Int) -> Int {
        draw()%m
    }
    mutating func chance(_ p: (Int, Int)) -> Bool {
        below(p.1)<p.0
    }
    mutating func shuffle(_ c: inout [Int]) {
        if c.count>1 {
            for n in stride(from: c.count, through: 2, by: -1) {
                let i = below(n);
                c.swapAt(n-1, i)
            }
        }
    }
}

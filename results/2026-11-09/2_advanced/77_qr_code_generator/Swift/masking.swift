import Foundation

func maskCondition(_ mask: Int, _ x: Int, _ y: Int) -> Bool {
    switch mask {
    case 0: return (y + x) % 2 == 0
    case 1: return y % 2 == 0
    case 2: return x % 3 == 0
    case 3: return (y + x) % 3 == 0
    case 4: return (y / 2 + x / 3) % 2 == 0
    case 5: return (y * x) % 2 + (y * x) % 3 == 0
    case 6: return ((y * x) % 2 + (y * x) % 3) % 2 == 0
    default: return ((y + x) % 2 + (y * x) % 3) % 2 == 0
    }
}

func applyMask(_ symbol: Symbol, positions: [Position], mask: Int) -> Symbol {
    var result = symbol
    for p in positions where maskCondition(mask, p.x, p.y) { result[p.y][p.x] ^= 1 }
    return result
}

struct Penalty {
    var n1 = 0, n2 = 0, n3 = 0, n4 = 0
    var total: Int { n1 + n2 + n3 + n4 }
}

func penaltyForSymbol(_ symbol: Symbol) -> Penalty {
    let size = symbol.count
    let patterns = [[1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0], [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1]]
    let lines = symbol + (0..<size).map { x in (0..<size).map { symbol[$0][x] } }
    var penalty = Penalty()
    for line in lines {
        var run = 1
        for index in 1..<size {
            if line[index] == line[index - 1] { run += 1 }
            else { if run >= 5 { penalty.n1 += run - 2 }; run = 1 }
        }
        if run >= 5 { penalty.n1 += run - 2 }
        for index in 0..<(size - 10) where patterns.contains(Array(line[index..<(index + 11)])) { penalty.n3 += 40 }
    }
    for y in 0..<(size - 1) {
        for x in 0..<(size - 1) {
            let value = symbol[y][x]
            if value == symbol[y][x + 1] && value == symbol[y + 1][x] && value == symbol[y + 1][x + 1] { penalty.n2 += 3 }
        }
    }
    let dark = symbol.reduce(0) { $0 + $1.reduce(0, +) }
    penalty.n4 = 10 * (abs(20 * dark - 10 * size * size) / (size * size))
    return penalty
}

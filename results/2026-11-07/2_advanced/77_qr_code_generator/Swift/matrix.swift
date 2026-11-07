import Foundation

typealias Symbol = [[Int]]

struct Position: Hashable {
    let x: Int
    let y: Int
    init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
}

enum Area {
    case data, function, format, version
}

func polynomialRemainder(_ value: Int, divisor: Int) -> Int {
    var remainder = value
    let divisorWidth = Int.bitWidth - divisor.leadingZeroBitCount
    while remainder != 0 && Int.bitWidth - remainder.leadingZeroBitCount >= divisorWidth {
        remainder ^= divisor << (Int.bitWidth - remainder.leadingZeroBitCount - divisorWidth)
    }
    return remainder
}

func formatInformation(_ level: String, _ mask: Int) -> Int {
    let indicator = ["L": 1, "M": 0, "Q": 3, "H": 2][level]!
    let shifted = (8 * indicator + mask) << 10
    return (shifted + polynomialRemainder(shifted, divisor: 0x537)) ^ 0x5412
}

func versionInformation(_ version: Int) -> Int {
    let shifted = version << 12
    return shifted + polynomialRemainder(shifted, divisor: 0x1f25)
}

func formatPositions(_ size: Int) -> [[Position]] {
    let first = (0..<6).map { Position(8, $0) } + [Position(8, 7), Position(8, 8), Position(7, 8)]
        + (9..<15).map { Position(14 - $0, 8) }
    let second = (0..<8).map { Position(size - 1 - $0, 8) } + (8..<15).map { Position(8, size - 15 + $0) }
    return [first, second]
}

func versionPositions(_ size: Int) -> [[Position]] {
    [(0..<18).map { Position(size - 11 + $0 % 3, $0 / 3) },
     (0..<18).map { Position($0 / 3, size - 11 + $0 % 3) }]
}

func writeValue(_ symbol: inout Symbol, positions: [Position], value: Int) {
    for (index, p) in positions.enumerated() { symbol[p.y][p.x] = (value >> index) & 1 }
}

func readValue(_ symbol: Symbol, positions: [Position]) -> Int {
    positions.enumerated().reduce(0) { $0 | (symbol[$1.element.y][$1.element.x] << $1.offset) }
}

func functionMatrix(_ version: Int, alignments: [Int]) -> (Symbol, [[Area]]) {
    let size = 17 + 4 * version
    var symbol = Array(repeating: Array(repeating: 0, count: size), count: size)
    var areas = Array(repeating: Array(repeating: Area.data, count: size), count: size)
    for center in [Position(3, 3), Position(size - 4, 3), Position(3, size - 4)] {
        for dy in -4...4 {
            for dx in -4...4 {
                let x = center.x + dx, y = center.y + dy
                if (0..<size).contains(x) && (0..<size).contains(y) {
                    symbol[y][x] = [0, 1, 3].contains(max(abs(dx), abs(dy))) ? 1 : 0
                    areas[y][x] = .function
                }
            }
        }
    }
    for index in 8..<(size - 8) {
        symbol[index][6] = index % 2 == 0 ? 1 : 0
        symbol[6][index] = symbol[index][6]
        areas[index][6] = .function
        areas[6][index] = .function
    }
    if let first = alignments.first, let last = alignments.last {
        let excluded: Set<Position> = [Position(first, first), Position(first, last), Position(last, first)]
        for cy in alignments {
            for cx in alignments where !excluded.contains(Position(cx, cy)) {
                for dy in -2...2 {
                    for dx in -2...2 {
                        symbol[cy + dy][cx + dx] = max(abs(dx), abs(dy)) != 1 ? 1 : 0
                        areas[cy + dy][cx + dx] = .function
                    }
                }
            }
        }
    }
    symbol[size - 8][8] = 1
    areas[size - 8][8] = .function
    for positions in formatPositions(size) {
        for p in positions { areas[p.y][p.x] = .format; symbol[p.y][p.x] = 0 }
    }
    if version >= 7 {
        for positions in versionPositions(size) {
            for p in positions { areas[p.y][p.x] = .version }
            writeValue(&symbol, positions: positions, value: versionInformation(version))
        }
    }
    return (symbol, areas)
}

func readingOrder(_ areas: [[Area]]) -> [Position] {
    let size = areas.count
    let columns = Array(stride(from: size - 1, through: 8, by: -2)) + [5, 3, 1]
    var positions: [Position] = []
    for (pair, right) in columns.enumerated() {
        let rows = pair % 2 == 0 ? Array((0..<size).reversed()) : Array(0..<size)
        for y in rows { for x in [right, right - 1] where areas[y][x] == .data { positions.append(Position(x, y)) } }
    }
    return positions
}

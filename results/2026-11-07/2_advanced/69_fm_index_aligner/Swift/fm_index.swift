import Foundation

struct Interval { let lower: Int; let upper: Int; var isEmpty: Bool { lower >= upper }; var count: Int { upper - lower } }
struct FMIndex {
    let size: Int
    let bwt: [UInt8]
    let interval: Int
    let cumulative: [Int]
    let checkpoints: [[Int]]
    let samples: [Int: Int]
    init(_ sequence: [UInt8], _ suffixes: [Int], _ interval: Int, _ sampleInterval: Int? = nil) {
        let transformed = suffixes.map { sequence[$0 == 0 ? sequence.count - 1 : $0 - 1] }
        size = sequence.count; bwt = transformed; self.interval = interval
        var frequencies = Array(repeating: 0, count: symbols.count), cumulative: [Int] = [], offset = 0
        for symbol in sequence { frequencies[symbolNumber(symbol)] += 1 }; for frequency in frequencies { cumulative.append(offset); offset += frequency }; self.cumulative = cumulative
        var counts = Array(repeating: 0, count: symbols.count), checkpoints = [counts], samples: [Int: Int] = [:]
        for (position, symbol) in transformed.enumerated() { counts[symbolNumber(symbol)] += 1; if (position + 1) % interval == 0 { checkpoints.append(counts) } }; self.checkpoints = checkpoints
        if let sampleInterval { for (row, position) in suffixes.enumerated() where position % sampleInterval == 0 { samples[row] = position } }; self.samples = samples
    }
    func occurrence(_ symbol: UInt8, _ position: Int) -> Int { let checkpoint = position / interval, start = checkpoint * interval; var count = checkpoints[checkpoint][symbolNumber(symbol)]; for index in start..<position where bwt[index] == symbol { count += 1 }; return count }
    func lf(_ row: Int) -> Int { cumulative[symbolNumber(bwt[row])] + occurrence(bwt[row], row) }
    func extend(_ range: Interval, _ base: UInt8) -> Interval { if base == 78 { return Interval(lower: 0, upper: 0) }; let first = cumulative[symbolNumber(base)]; return Interval(lower: first + occurrence(base, range.lower), upper: first + occurrence(base, range.upper)) }
    func locate(_ row: Int) -> (position: Int, steps: Int) { var row = row, steps = 0; while samples[row] == nil { row = lf(row); steps += 1 }; return (samples[row]! + steps, steps) }
    func inverse() -> [UInt8] { var result = Array(repeating: UInt8(36), count: size), row = 0; if size > 1 { for position in stride(from: size - 2, through: 0, by: -1) { result[position] = bwt[row]; row = lf(row) } }; return result }
    func backwardSearch(_ sequence: [UInt8]) -> Interval { var range = Interval(lower: 0, upper: size); for base in sequence.reversed() { range = extend(range, base); if range.isEmpty { break } }; return range }
}

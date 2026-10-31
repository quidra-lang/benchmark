import Foundation

struct CacheLine: Equatable {
    let block: Int
    var state: CacheState
}

final class Cache {
    let sets: Int, ways: Int
    let replacement: Replacement
    var entries: [[CacheLine?]]
    var touched: [[Int]], bits: [[Int]]
    var fills: [Int], evictions: [Int]
    var clock = 0

    init(sets: Int, ways: Int, replacement: Replacement) {
        self.sets = sets; self.ways = ways; self.replacement = replacement
        entries = Array(repeating: Array(repeating: nil, count: ways), count: sets)
        touched = Array(repeating: Array(repeating: 0, count: ways), count: sets)
        bits = touched
        fills = Array(repeating: 0, count: sets); evictions = fills
    }

    func locate(_ block: Int) -> (Int, Int)? {
        let row = block % sets
        if let way = entries[row].firstIndex(where: { $0?.block == block }) { return (row, way) }
        return nil
    }
    func state(_ block: Int) -> CacheState {
        guard let (row, way) = locate(block) else { return .invalid }
        return entries[row][way]!.state
    }
    func change(_ block: Int, _ state: CacheState) {
        if let (row, way) = locate(block) { entries[row][way]!.state = state }
    }
    func touchWay(_ row: Int, _ way: Int, fill: Bool) {
        if replacement == .lru || (replacement == .fifo && fill) {
            clock += 1; touched[row][way] = clock
        } else if replacement == .plru {
            var low = 0, high = ways, node = 1
            while high - low > 1 {
                let mid = (low + high) / 2
                if way < mid { bits[row][node] = 1; high = mid; node *= 2 }
                else { bits[row][node] = 0; low = mid; node = node * 2 + 1 }
            }
        }
    }
    func touch(_ block: Int) { if let (row, way) = locate(block) { touchWay(row, way, fill: false) } }
    func victim(_ row: Int) -> Int {
        if replacement == .plru {
            var low = 0, high = ways, node = 1
            while high - low > 1 {
                let mid = (low + high) / 2
                if bits[row][node] == 0 { high = mid; node *= 2 } else { low = mid; node = node * 2 + 1 }
            }
            return low
        }
        var chosen = 0
        for way in 1..<ways where touched[row][way] < touched[row][chosen] { chosen = way }
        return chosen
    }
    func fill(_ block: Int, _ state: CacheState) -> CacheLine? {
        let row = block % sets, way = entries[block % sets].firstIndex(where: { $0 == nil }) ?? victim(block % sets)
        let old = entries[row][way]
        if old != nil { evictions[row] += 1 }
        entries[row][way] = CacheLine(block: block, state: state)
        fills[row] += 1
        touchWay(row, way, fill: true)
        return old
    }
    @discardableResult func remove(_ block: Int) -> CacheLine? {
        guard let (row, way) = locate(block) else { return nil }
        let old = entries[row][way]
        entries[row][way] = nil
        return old
    }
    func order(_ row: Int) -> String {
        if replacement == .plru { return ways == 1 ? "-" : bits[row].dropFirst().map(String.init).joined() }
        let active = (0..<ways).filter { entries[row][$0] != nil }.sorted {
            touched[row][$0] == touched[row][$1] ? $0 < $1 : touched[row][$0] > touched[row][$1]
        }
        return active.isEmpty ? "-" : active.map(String.init).joined(separator: " ")
    }
    var lines: [CacheLine] { entries.flatMap { $0.compactMap { $0 } } }
}

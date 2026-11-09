import Foundation

enum Mode: String, CaseIterable {
    case chain = "CHAIN", linear = "LINEAR", quadratic = "QUADRATIC", double = "DOUBLE"
    case robinHood = "ROBINHOOD", cuckoo = "CUCKOO"
    var usesTombstones: Bool {
        self == .linear || self == .quadratic || self == .double
    }
    var parts: Int {
        self == .cuckoo ? 2 : 1
    }
}
let commands: Set<String> = [
    "CREATE",
    "MAXLOAD",
    "MINLOAD",
    "TRACE",
    "HASH",
    "PUT",
    "ADD",
    "GET",
    "DEL",
    "PROBE",
    "GEN",
    "GENDEL",
    "RESIZE",
    "CONVERT",
    "CLEAR",
    "DUMP",
    "MAP",
    "STATS",
    "KEYS",
    "TOP",
    "SCAN",
    "CLUSTERS",
    "DIST",
    "COMPARE",
    "BENCH"
]
struct CommandError: Error {
    let message: String
    init(_ message: String) {
        self.message = message
    }
}
struct Item {
    let key: String
    let value: Int
    var text: String {
        "\(key)=\(value)"
    }
}
enum Slot {
    case empty, item(Item), tombstone
    var entry: Item? {
        if case let .item(item) = self {
            return item
        }
        return nil
    }
    var isEmpty: Bool {
        if case .empty = self {
            return true
        }
        return false
    }
    var isTombstone: Bool {
        if case .tombstone = self {
            return true
        }
        return false
    }
    var content: String {
        entry?.key ?? (isEmpty ? "-" : "D")
    }
}
func hash(_ key: String, _ base: Int, _ modulus: Int) -> Int {
    key.utf8.reduce(0) { ($0 * base + Int($1)) % modulus }
}
func prime(_ value: Int) -> Int {
    var candidate = max(2, value)
    while true {
        var valid = true, divisor = 2
        while divisor * divisor <= candidate {
            if candidate % divisor == 0 {
                valid = false
                break
            }
            divisor += 1
        }
        if valid {
            return candidate
        }
        candidate += 1
    }
}
func padded(_ value: Int, _ width: Int) -> String {
    let text = String(value)
    return String(repeating: "0", count: max(0, width - text.count)) + text
}
func decimal(_ numerator: Int, _ denominator: Int) -> String {
    let value = denominator == 0 ? 0 : 100 * numerator / denominator
    return "\(value / 100)." + padded(value % 100, 2)
}
func gauge(_ value: Int) -> Character {
    value < 10 ? Character(String(value)) : "+"
}
func generatedKeys(_ count: Int, _ length: Int, _ seed: Int) -> [String] {
    var state = seed, keys: [String] = []
    for _ in 0..<count {
        var bytes: [UInt8] = []
        for _ in 0..<length {
            state = 48271 * state % 2147483647
            bytes.append(UInt8(97 + state % 26))
        }
        keys.append(String(decoding: bytes, as: UTF8.self))
    }
    return keys
}
func histogram(_ values: [Int]) -> [String] {
    var counts: [Int: Int] = [:]
    for value in values {
        counts[value, default: 0] += 1
    }
    return counts.keys.sorted().map { value in
        let count = counts[value]!
        return "\(value) \(count) " + String(repeating: "#", count: min(count, 50)) + (count > 50 ? "+" : "")
    }
}
func runs(_ slots: [Slot], start: Int, count: Int) -> [Int] {
    guard let empty = (0..<count).first(where: { slots[start + $0].isEmpty }) else {
        return [count]
    }
    var lengths: [Int] = [], length = 0
    for offset in 1...count {
        if !slots[start + (empty + offset) % count].isEmpty {
            length += 1
        } else if length > 0 {
            lengths.append(length)
            length = 0
        }
    }
    return lengths
}
struct Counters {
    var probes = 0, rehashes = 0, inserts = 0, updates = 0
    var hits = 0, misses = 0, deletes = 0, absent = 0
}
struct Search {
    var item: Item?
    var position = -1, chainIndex = -1, probes = 0
    var available: Int?
    var path: [String] = []
}
struct Placement {
    var success = false, reused = false
    var position = -1, shifted = 0, kicks = 0
    var homeless: Item?
    var moves: [String] = []
}
struct Removal { var shifted = 0
    var moves: [String] = []
}
struct PutResult { let fresh: Bool
    let rehashes, rows: [String]
}
struct DeleteResult { let deleted: Bool
    let rehashes, rows: [String]
}
struct Cost { let key: String
    let cost, position: Int
}
struct Metrics { let longest: Int
    let average: String
}

final class Table {
    private(set) var mode: Mode
    private(set) var cap: Int
    private(set) var size = 0, tomb = 0
    private(set) var counters = Counters()
    private var buckets: [[Item]]
    private var slots: [Slot]
    init(_ mode: Mode, _ capacity: Int) {
        self.mode = mode
        cap = capacity
        buckets = mode == .chain ? Array(repeating: [], count: capacity) : []
        slots = mode == .chain ? [] : Array(repeating: .empty, count: capacity * mode.parts)
    }
    var slotCount: Int {
        cap * mode.parts
    }
    func position(_ index: Int) -> String {
        mode == .cuckoo ? "T\(index / cap + 1).\(index % cap)" : String(index)
    }
    func distance(_ key: String, _ position: Int) -> Int {
        (position - hash(key, 31, cap) + cap) % cap
    }
    func items() -> [Item] {
        mode == .chain ? buckets.flatMap { $0 } : slots.compactMap { $0.entry }
    }
    func search(_ key: String, tracing: Bool = false) -> Search {
        var result = Search()
        let first = hash(key, 31, cap)
        func examine(_ index: Int, _ slot: Slot) {
            result.probes += 1
            if tracing {
                result.path.append("\(position(index)):\(slot.content)")
            }
        }
        func found(_ item: Item, _ position: Int, _ chainIndex: Int = -1) {
            result.item = item
            result.position = position
            result.chainIndex = chainIndex
        }
        if mode == .chain {
            for (index, item) in buckets[first].enumerated() {
                examine(first, .item(item))
                if item.key == key {
                    found(item, first, index)
                    break
                }
            }
            return result
        }
        if mode == .cuckoo {
            for index in [first, cap + hash(key, 37, cap)] {
                examine(index, slots[index])
                if let item = slots[index].entry, item.key == key {
                    found(item, index)
                    break
                }
            }
            return result
        }
        let step = mode == .double ? 1 + hash(key, 37, cap - 1) : 1
        for i in 0..<cap {
            let offset = mode == .quadratic ? i * i : i * step
            let index = (first + offset) % cap, slot = slots[index]
            examine(index, slot)
            if slot.isEmpty {
                if result.available == nil {
                    result.available = index
                }
                break
            }
            if slot.isTombstone {
                if result.available == nil {
                    result.available = index
                }
                continue
            }
            let item = slot.entry!
            if item.key == key {
                found(item, index)
                break
            }
            if mode == .robinHood && distance(item.key, index) < i {
                break
            }
        }
        return result
    }
    func place(_ item: Item, initial: Search? = nil, tracing: Bool = false) -> Placement {
        var result = Placement()
        if mode == .chain {
            result.position = hash(item.key, 31, cap)
            buckets[result.position].append(item)
            result.success = true
            return result
        }
        if mode.usesTombstones {
            let found = initial ?? search(item.key)
            guard let index = found.available else {
                result.homeless = item
                return result
            }
            result.position = index
            result.reused = slots[index].isTombstone
            slots[index] = .item(item)
            if result.reused {
                tomb -= 1
            }
            result.success = true
            return result
        }
        var current = item
        if mode == .robinHood {
            var index = hash(item.key, 31, cap), dist = 0
            var from: Int?
            while true {
                guard let occupant = slots[index].entry else {
                    slots[index] = .item(current)
                    if tracing, let from {
                        result.moves.append("SHIFT \(current.key) \(from) -> \(index)")
                    }
                    if result.position < 0 {
                        result.position = index
                    }
                    result.success = true
                    return result
                }
                let otherDistance = distance(occupant.key, index)
                if otherDistance < dist {
                    slots[index] = .item(current)
                    if tracing, let from {
                        result.moves.append("SHIFT \(current.key) \(from) -> \(index)")
                    }
                    if result.position < 0 {
                        result.position = index
                    }
                    current = occupant
                    from = index
                    dist = otherDistance
                    result.shifted += 1
                }
                index = (index + 1) % cap
                dist += 1
            }
        }
        var part = 0
        while true {
            let index = part * cap + hash(current.key, part == 0 ? 31 : 37, cap)
            guard let occupant = slots[index].entry else {
                slots[index] = .item(current)
                result.success = true
                result.position = search(item.key).position
                return result
            }
            if result.kicks == cap {
                result.homeless = current
                return result
            }
            slots[index] = .item(current)
            result.kicks += 1
            if tracing {
                result.moves.append("KICK \(occupant.key) \(position(index))")
            }
            current = occupant
            part = 1 - part
        }
    }
    func remove(_ found: Search, tracing: Bool) -> Removal {
        var result = Removal()
        if mode == .chain {
            buckets[found.position].remove(at: found.chainIndex)
        } else if mode.usesTombstones {
            slots[found.position] = .tombstone
            tomb += 1
        } else {
            slots[found.position] = .empty
            if mode == .robinHood {
                var next = (found.position + 1) % cap
                while let item = slots[next].entry, distance(item.key, next) >= 1 {
                    let destination = (next - 1 + cap) % cap
                    slots[destination] = .item(item)
                    slots[next] = .empty
                    if tracing {
                        result.moves.append("SHIFT \(item.key) \(next) -> \(destination)")
                    }
                    result.shifted += 1
                    next = (next + 1) % cap
                }
            }
        }
        size -= 1
        return result
    }
    static func rebuild(_ items: [Item], mode: Mode, capacity: Int) -> Table? {
        let table = Table(mode, capacity)
        for item in items {
            if !table.place(item).success {
                return nil
            }
            table.size += 1
        }
        return table
    }
    func adopt(_ replacement: Table) {
        mode = replacement.mode
        cap = replacement.cap
        size = replacement.size
        tomb = replacement.tomb
        buckets = replacement.buckets
        slots = replacement.slots
    }
    func automatic(_ reason: String, capacity: Int, pending: Item? = nil) -> String {
        var listed = items(), target = capacity
        if let pending {
            listed.append(pending)
        }
        let old = cap
        while true {
            if let replacement = Table.rebuild(listed, mode: mode, capacity: target) {
                adopt(replacement)
                counters.rehashes += 1
                return "REHASH \(reason) \(old) -> \(cap)"
            }
            target = prime(2 * target)
        }
    }
    func loadCheck(_ maxLoad: Int) -> [String] {
        let threshold = maxLoad * slotCount
        if 100 * (size + tomb) <= threshold {
            return []
        }
        let grow = 200 * size > threshold
        return [automatic(grow ? "load" : "tomb", capacity: grow ? prime(2 * cap) : cap)]
    }
    func shrinkCheck(_ minLoad: Int, _ maxLoad: Int) -> [String] {
        let capacity = prime(cap / 2), newSlots = capacity * mode.parts
        if 100 * size >= minLoad * slotCount || capacity >= cap || 100 * size > maxLoad * newSlots {
            return []
        }
        guard let replacement = Table.rebuild(items(), mode: mode, capacity: capacity) else {
            return []
        }
        let old = cap
        adopt(replacement)
        counters.rehashes += 1
        return ["REHASH shrink \(old) -> \(capacity)"]
    }
    func put(_ key: String, _ value: Int, command: String, maxLoad: Int, tracing: Bool = false) -> PutResult {
        let found = search(key, tracing: tracing)
        let trace = tracing ? ["PATH " + (found.path.isEmpty ? "none" : found.path.joined(separator: " "))] : []
        counters.probes += found.probes
        if let old = found.item?.value {
            let item = Item(key: key, value: command == "ADD" ? old + value : value)
            if mode == .chain {
                buckets[found.position][found.chainIndex] = item
            } else {
                slots[found.position] = .item(item)
            }
            counters.updates += 1
            let row = "\(command) \(item.text) UPDATED old=\(old) at=\(position(found.position)) probes=\(found.probes)"
            return PutResult(fresh: false, rehashes: [], rows: [row] + trace)
        }
        let item = Item(key: key, value: value), placed = place(item, initial: found, tracing: tracing)
        size += 1
        counters.inserts += 1
        var row = "\(command) \(item.text) NEW"
        if placed.success {
            row += " at=\(position(placed.position)) probes=\(found.probes)"
            if placed.reused {
                row += " reused"
            }
            if mode == .robinHood {
                row += " shifted=\(placed.shifted)"
            }
            if mode == .cuckoo {
                row += " kicks=\(placed.kicks)"
            }
        } else {
            row += " probes=\(found.probes)" + (mode == .cuckoo ? " kicks=\(placed.kicks) failed" : " full")
        }
        var rehashes: [String] = []
        if !placed.success {
            rehashes.append(automatic(
                mode == .cuckoo ? "kicks" : "full",
                capacity: prime(2 * cap),
                pending: placed.homeless
            ))
        }
        rehashes += loadCheck(maxLoad)
        return PutResult(fresh: true, rehashes: rehashes, rows: [row] + trace + placed.moves + rehashes)
    }
    func get(_ key: String, tracing: Bool) -> [String] {
        let found = search(key, tracing: tracing)
        counters.probes += found.probes
        var row: String
        if let item = found.item {
            counters.hits += 1
            row = "GET \(item.text) at=\(position(found.position))"
        } else {
            counters.misses += 1
            row = "GET \(key) NOT FOUND"
        }
        row += " probes=\(found.probes)"
        return tracing ? [row, "PATH " + (found.path.isEmpty ? "none" : found.path.joined(separator: " "))] : [row]
    }
    func delete(_ key: String, minLoad: Int, maxLoad: Int, tracing: Bool = false) -> DeleteResult {
        let found = search(key, tracing: tracing)
        let trace = tracing ? ["PATH " + (found.path.isEmpty ? "none" : found.path.joined(separator: " "))] : []
        counters.probes += found.probes
        if found.item == nil {
            counters.absent += 1
            return DeleteResult(
                deleted: false,
                rehashes: [],
                rows: ["DEL \(key) NOT FOUND probes=\(found.probes)"] + trace
            )
        }
        let removed = remove(found, tracing: tracing)
        counters.deletes += 1
        var row = "DEL \(key) OK at=\(position(found.position)) probes=\(found.probes)"
        if mode == .robinHood {
            row += " shifted=\(removed.shifted)"
        }
        let rehashes = shrinkCheck(minLoad, maxLoad)
        return DeleteResult(deleted: true, rehashes: rehashes, rows: [row] + trace + removed.moves + rehashes)
    }
    func costs() -> [Cost] {
        var records: [Cost] = []
        if mode == .chain {
            for (position, bucket) in buckets.enumerated() {
                for (index, item) in bucket.enumerated() {
                    records.append(Cost(
                        key: item.key,
                        cost: index + 1,
                        position: position
                    ))
                }
            }
        } else {
            for (position, slot) in slots.enumerated() {
                guard let item = slot.entry else {
                    continue
                }
                let cost = mode == .cuckoo ? (position < cap ? 1 : 2)
                    : mode == .linear || mode == .robinHood ? distance(item.key, position) + 1 : search(item.key).probes
                records.append(Cost(key: item.key, cost: cost, position: position))
            }
        }
        return records
    }
    func metrics() -> Metrics {
        let values = costs().map { $0.cost }
        return Metrics(longest: values.max() ?? 0, average: decimal(values.reduce(0, +), size))
    }
    func dump() -> [String] {
        var rows = ["DUMP \(mode.rawValue) cap=\(cap) size=\(size) tomb=\(tomb)"]
        if mode == .chain {
            for (index, bucket) in buckets.enumerated() {
                rows.append("\(index) " + (bucket.isEmpty ? "-" : bucket.map { $0.text }.joined(separator: " ")))
            }
        } else {
            for (index, slot) in slots.enumerated() {
                let position = mode == .cuckoo ? "T\(index / cap + 1) \(index % cap)" : String(index)
                var value = slot.entry?.text ?? slot.content
                if mode == .robinHood, let item = slot.entry {
                    value += " d=\(distance(item.key, index))"
                }
                rows.append(position + " " + value)
            }
        }
        return rows
    }
    func map() -> [String] {
        var rows = ["MAP \(mode.rawValue) cap=\(cap)"], costBySlot = Array(repeating: 0, count: slotCount)
        if mode != .chain {
            for record in costs() {
                costBySlot[record.position] = record.cost
            }
        }
        for part in 0..<mode.parts {
            var characters: [Character] = []
            for index in 0..<cap {
                if mode == .chain {
                    characters.append(buckets[index].isEmpty ? "." : gauge(buckets[index].count))
                } else {
                    let flat = part * cap + index, slot = slots[flat]
                    characters
                        .append(slot.isEmpty ? "." : slot
                            .isTombstone ? "D" : mode == .cuckoo ? "#" : gauge(costBySlot[flat] - 1))
                }
            }
            for index in stride(from: 0, to: cap, by: 40) {
                let prefix = mode == .cuckoo ? "T\(part + 1) " : ""
                rows.append(prefix + padded(index, 5) + " " + String(characters[index..<min(index + 40, cap)]))
            }
        }
        return rows
    }
    func statistics() -> [String] {
        let values = metrics(), count = counters
        return [
            "STATS \(mode.rawValue) size=\(size) cap=\(cap) slots=\(slotCount) tomb=\(tomb) load=\(decimal(100 * size, slotCount))% longest=\(values.longest) avg=\(values.average) probes=\(count.probes) rehashes=\(count.rehashes)",
            "OPS inserts=\(count.inserts) updates=\(count.updates) hits=\(count.hits) misses=\(count.misses) deletes=\(count.deletes) absent=\(count.absent)"
        ]
    }
    func scan(_ cursor: Int, _ limit: Int) -> [String] {
        var keys: [String] = [], next = cursor
        while next < slotCount && keys.count < limit {
            if mode == .chain {
                keys += buckets[next].map { $0.key }
            } else if let item = slots[next].entry {
                keys.append(item.key)
            }
            next += 1
        }
        if next == slotCount {
            next = 0
        }
        return [(["SCAN next=\(next)"] + keys).joined(separator: " ")]
    }
    func clusters() -> [String] {
        var lengths: [Int]
        if mode == .chain {
            lengths = buckets.filter { !$0.isEmpty }.map { $0.count }
        } else {
            lengths = runs(slots, start: 0, count: cap)
            if mode == .cuckoo {
                lengths += runs(slots, start: cap, count: cap)
            }
        }
        return ["CLUSTERS runs=\(lengths.count) longest=\(lengths.max() ?? 0)"] + histogram(lengths)
    }
    func distribution() -> [String] {
        let values = costs().map { $0.cost }
        return ["DIST keys=\(size) longest=\(values.max() ?? 0)"] + histogram(values)
    }
}

func checkedMode(_ name: String) throws -> Mode {
    guard let mode = Mode(rawValue: name) else {
        throw CommandError("BAD MODE " + name)
    }
    return mode
}
func checkCapacity(_ capacity: Int) throws {
    if !(2...10000).contains(capacity) {
        throw CommandError("BAD CAPACITY")
    }
}
func checkGeneration(_ count: Int, _ length: Int, _ seed: Int) throws {
    if !(1...500).contains(count) || !(1...10).contains(length) || !(1...2147483646)
        .contains(seed)
    {
        throw CommandError("BAD ARGUMENT")
    }
}
final class Simulator {
    private var table: Table?
    private var maxLoad = 75, minLoad = 0
    private var tracing = false
    func compare(_ capacity: Int) -> [String] {
        let items = table!.items().sorted { $0.key < $1.key }
        var rows = ["COMPARE keys=\(items.count) cap=\(capacity)"]
        for mode in Mode.allCases {
            let experiment = Table(mode, capacity)
            for item in items {
                _ = experiment.put(item.key, item.value, command: "PUT", maxLoad: maxLoad)
            }
            let values = experiment.metrics()
            rows
                .append(
                    "\(mode.rawValue) cap=\(experiment.cap) longest=\(values.longest) avg=\(values.average) probes=\(experiment.counters.probes) rehashes=\(experiment.counters.rehashes)"
                )
        }
        return rows
    }
    func bench(_ capacity: Int, _ count: Int, _ length: Int, _ seed: Int) -> [String] {
        let keys = generatedKeys(2 * count, length, seed)
        var rows = ["BENCH cap=\(capacity) count=\(count) len=\(length) seed=\(seed)"]
        for mode in Mode.allCases {
            let experiment = Table(mode, capacity)
            for index in 0..<count {
                _ = experiment.put(keys[index], index + 1, command: "PUT", maxLoad: maxLoad)
            }
            var misses = 0, probes = 0
            for index in count..<(2 * count) {
                let found = experiment.search(keys[index])
                if found.item == nil {
                    misses += 1
                    probes += found.probes
                }
            }
            rows
                .append(
                    "\(mode.rawValue) cap=\(experiment.cap) keys=\(experiment.size) hit=\(experiment.metrics().average) misses=\(misses) miss=\(decimal(probes, misses)) rehashes=\(experiment.counters.rehashes)"
                )
        }
        return rows
    }
    func execute(_ line: String) throws -> [String] {
        let words = line.split(separator: " ").map(String.init), command = words[0]
        let args = Array(words.dropFirst())
        if !commands.contains(command) {
            throw CommandError("UNKNOWN COMMAND " + command)
        }
        if command == "CREATE" {
            let mode = try checkedMode(args[0]), capacity = Int(args[1])!
            try checkCapacity(capacity)
            let replacement = Table(mode, prime(capacity))
            self.table = replacement
            return ["CREATE \(mode.rawValue) cap=\(replacement.cap)"]
        }
        if command == "MAXLOAD" || command == "MINLOAD" {
            let value = Int(args[0])!, maximum = command == "MAXLOAD"
            if maximum ? !(10...95).contains(value) : !(0...40).contains(value) {
                throw CommandError("BAD LOAD")
            }
            if maximum {
                maxLoad = value
            } else {
                minLoad = value
            }
            return ["\(command) \(value)"]
        }
        if command == "TRACE" {
            if args[0] != "ON" && args[0] != "OFF" {
                throw CommandError("BAD ARGUMENT")
            }
            tracing = args[0] == "ON"
            return ["TRACE " + args[0]]
        }
        if command == "HASH" {
            let key = args[0], capacity = Int(args[1])!
            try checkCapacity(capacity)
            return [
                "HASH \(key) m=\(capacity) h31=\(hash(key, 31, capacity)) h37=\(hash(key, 37, capacity)) step=\(1 + hash(key, 37, capacity - 1))"
            ]
        }
        if command == "BENCH" {
            let capacity = Int(args[0])!, count = Int(args[1])!, length = Int(args[2])!, seed = Int(args[3])!
            try checkCapacity(capacity)
            try checkGeneration(count, length, seed)
            return bench(prime(capacity), count, length, seed)
        }
        guard let table = self.table else {
            throw CommandError("NO TABLE")
        }
        switch command {
        case "PUT",
             "ADD":
            return table.put(args[0], Int(args[1])!, command: command, maxLoad: maxLoad, tracing: tracing).rows
        case "GET":
            return table.get(args[0], tracing: tracing)
        case "DEL":
            return table.delete(args[0], minLoad: minLoad, maxLoad: maxLoad, tracing: tracing).rows
        case "PROBE":
            let found = table.search(args[0], tracing: true)
            return [(["PROBE " + args[0]] + found
                    .path + ["\(found.item == nil ? "MISS" : "FOUND") probes=\(found.probes)"]).joined(separator: " ")]
        case "GEN", "GENDEL":
            let count = Int(args[0])!, length = Int(args[1])!, seed = Int(args[2])!
            try checkGeneration(count, length, seed)
            let keys = generatedKeys(count, length, seed)
            var rows: [String] = [], successes = 0
            for (index, key) in keys.enumerated() {
                if command == "GEN" {
                    let result = table.put(key, index + 1, command: "PUT", maxLoad: maxLoad)
                    if result.fresh {
                        successes += 1
                    }
                    rows += result.rehashes
                } else {
                    let result = table.delete(key, minLoad: minLoad, maxLoad: maxLoad)
                    if result.deleted {
                        successes += 1
                    }
                    rows += result.rehashes
                }
            }
            rows
                .append(command == "GEN" ? "GEN \(count) new=\(successes) updated=\(count - successes)" :
                    "GENDEL \(count) deleted=\(successes) missing=\(count - successes)")
            return rows
        case "RESIZE", "CONVERT":
            var mode = table.mode, capacity = table.cap
            if command == "RESIZE" {
                capacity = Int(args[0])!
                try checkCapacity(capacity)
                capacity = prime(capacity)
            } else {
                mode = try checkedMode(args[0])
            }
            if 100 * table.size > maxLoad * capacity * mode.parts {
                throw CommandError("TOO SMALL")
            }
            guard let replacement = Table.rebuild(table.items(), mode: mode, capacity: capacity)
            else {
                throw CommandError("REBUILD FAILED")
            }
            let row = command == "RESIZE" ? "RESIZE \(table.cap) -> \(capacity)" : "CONVERT \(table.mode.rawValue) -> \(mode.rawValue) cap=\(capacity)"
            table.adopt(replacement)
            return [row]
        case "CLEAR":
            let size = table.size
            table.adopt(Table(table.mode, table.cap))
            return ["CLEAR \(size)"]
        case "DUMP":
            return table.dump()
        case "MAP":
            return table.map()
        case "STATS":
            return table.statistics()
        case "KEYS":
            return [(["KEYS \(table.size)"] + table.items().map { $0.key }.sorted()).joined(separator: " ")]
        case "TOP":
            let limit = Int(args[0])!
            if !(1...100).contains(limit) {
                throw CommandError("BAD ARGUMENT")
            }
            let records = table.costs().sorted { $0.cost != $1.cost ? $0.cost > $1.cost : $0.key < $1.key }
                .prefix(limit)
            return ["TOP \(records.count)"] + records
                .map { "\($0.key) cost=\($0.cost) at=\(table.position($0.position))" }
        case "SCAN":
            let cursor = Int(args[0])!, limit = Int(args[1])!
            if !(1...100).contains(limit) {
                throw CommandError("BAD ARGUMENT")
            }
            if cursor >= table.slotCount {
                throw CommandError("BAD CURSOR")
            }
            return table.scan(cursor, limit)
        case "CLUSTERS":
            return table.clusters()
        case "DIST":
            return table.distribution()
        case "COMPARE":
            let capacity = Int(args[0])!
            try checkCapacity(capacity)
            return compare(prime(capacity))
        default:
            preconditionFailure("Unhandled command " + command)
        }
    }
}

let count = Int(readLine()!)!, simulator = Simulator()
for _ in 0..<count {
    let line = readLine()!
    do {
        let rows = try simulator.execute(line)
        FileHandle.standardOutput.write(Data((rows.joined(separator: "\n") + "\n").utf8))
    } catch let error as CommandError {
        FileHandle.standardOutput.write(Data(("ERROR " + error.message + "\n").utf8))
    } catch {
        fatalError(String(describing: error))
    }
}

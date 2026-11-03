import Foundation

let modes = ["FIRST", "NEXT", "BEST", "WORST", "SEGFIT", "BUDDY"]
let counterNames = ["allocs", "frees", "reallocs", "moves", "failures", "collected"]
let unit = 8
let header = 8
let minBlock = 16
let minBuddyBlock = 32
let maxHeap = 65536
let uninitialized = -1
let randomMultiplier = 48271
let randomModulus = 2147483647

struct CommandError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

func isPowerOfTwo(_ n: Int) -> Bool { n > 0 && (n & (n - 1)) == 0 }
func sizeClass(_ n: Int) -> Int {
    var result = 0
    while (1 << (result + 1)) <= n { result += 1 }
    return result
}
func fragmentationPercent(_ free: Int, _ largest: Int) -> Int {
    free == 0 ? 0 : (free - largest) * 100 / free
}
func nextRandom(_ state: Int) -> Int { randomMultiplier * state % randomModulus }

final class Block {
    var start: Int
    var size: Int
    var used = false
    var owner: String?
    var requested = 0
    var contents: [Int] = []
    var stamp = 0

    init(_ start: Int, _ size: Int) { self.start = start; self.size = size }
    var end: Int { start + size }
    var payload: Int { start + header }
    var area: String { "\(start)+\(size)" }
    var mapUnits: String {
        var result = used ? "H" : "F"
        for i in 0..<(size / unit - 1) {
            result += !used ? "." : i * unit < requested ? "#" : "-"
        }
        return result
    }
}

struct Choice {
    let index: Int
    let place: Int
    let rank: (Int, Int)
}
struct Move {
    let block: Block
    let from: Int
}

final class Heap {
    let mode: String
    var size: Int
    var rover = 0
    private var registrations = 0
    var blocks: [Block] = []

    init(_ mode: String, _ size: Int) {
        self.mode = mode
        self.size = size
        blocks = [register(Block(0, size))]
    }
    private func register(_ block: Block) -> Block {
        registrations += 1
        block.stamp = registrations
        return block
    }
    var buddy: Bool { mode == "BUDDY" }
    func requiredLength(_ request: Int) -> Int {
        let length = (request + unit - 1) / unit * unit + header
        if !buddy { return length }
        var power = minBuddyBlock
        while power < length { power *= 2 }
        return power
    }
    func locate(_ address: Int) -> Int {
        var index = 0
        while blocks[index].end <= address { index += 1 }
        return index
    }
    func indexOf(_ block: Block) -> Int { blocks.firstIndex { $0 === block }! }
    var usedBlocks: [Block] { blocks.filter { $0.used } }
    var freeBlocks: [Block] { blocks.filter { !$0.used } }
    var usedTotal: Int { usedBlocks.reduce(0) { $0 + $1.size } }
    var fragmentation: Int {
        let free = freeBlocks
        return fragmentationPercent(free.reduce(0) { $0 + $1.size },
                                    free.map(\.size).max() ?? 0)
    }
    func placement(_ block: Block, _ alignment: Int) -> Int {
        var p = (block.start + header + alignment - 1) / alignment * alignment - header
        if p > block.start && p - block.start < minBlock { p += alignment }
        return p
    }
    func rank(_ index: Int, _ roverIndex: Int) -> (Int, Int) {
        let block = blocks[index]
        switch mode {
        case "NEXT": return ((index - roverIndex + blocks.count) % blocks.count, 0)
        case "BEST", "BUDDY": return (block.size, block.start)
        case "WORST": return (-block.size, block.start)
        case "SEGFIT": return (sizeClass(block.size), -block.stamp)
        default: return (block.start, 0)
        }
    }
    func choose(_ length: Int, _ alignment: Int) -> Choice? {
        let roverIndex = locate(rover)
        var selected: Choice?
        for index in blocks.indices {
            let block = blocks[index]
            if block.used { continue }
            let place = placement(block, alignment)
            if place + length > block.end { continue }
            let r = rank(index, roverIndex)
            if let previous = selected {
                if r.0 > previous.rank.0 || (r.0 == previous.rank.0 && r.1 >= previous.rank.1) {
                    continue
                }
            }
            selected = Choice(index: index, place: place, rank: r)
        }
        return selected
    }
    func allocate(_ length: Int, _ alignment: Int) -> Block? {
        guard let selected = choose(length, alignment) else { return nil }
        let block = buddy ? halve(selected.index, length) : carve(selected.index, selected.place, length)
        block.used = true
        if mode == "NEXT" { rover = block.end == size ? 0 : block.end }
        return block
    }
    func carve(_ index: Int, _ place: Int, _ length: Int) -> Block {
        let previous = blocks[index]
        var parts: [Block] = []
        if place > previous.start {
            parts.append(register(Block(previous.start, place - previous.start)))
        }
        let block = Block(place, previous.end - place)
        parts.append(block)
        if block.size - length >= minBlock {
            parts.append(register(Block(place + length, block.size - length)))
            block.size = length
        }
        blocks.replaceSubrange(index..<(index + 1), with: parts)
        return block
    }
    func halve(_ index: Int, _ length: Int) -> Block {
        let block = blocks[index]
        while block.size > length {
            block.size /= 2
            blocks.insert(register(Block(block.end, block.size)), at: index + 1)
        }
        return block
    }
    private func mergeNext(_ index: Int) {
        blocks[index].size += blocks.remove(at: index + 1).size
    }
    func coalesce(_ firstIndex: Int) -> (Block, Int) {
        var index = firstIndex
        var merges = 0
        if buddy {
            while blocks[index].size < size {
                let block = blocks[index]
                let partner = block.start % (2 * block.size) == 0 ? index + 1 : index - 1
                if partner < 0 || partner >= blocks.count { break }
                let other = blocks[partner]
                if other.used || other.size != block.size { break }
                index = min(index, partner)
                mergeNext(index)
                merges += 1
            }
        } else {
            if index + 1 < blocks.count && !blocks[index + 1].used {
                mergeNext(index)
                merges += 1
            }
            if index > 0 && !blocks[index - 1].used {
                index -= 1
                mergeNext(index)
                merges += 1
            }
        }
        return (register(blocks[index]), merges)
    }
    func release(_ block: Block) -> (Block, Int) {
        block.used = false
        block.owner = nil
        block.requested = 0
        block.contents = []
        return coalesce(indexOf(block))
    }
    func shrink(_ index: Int, _ length: Int) -> String {
        let block = blocks[index]
        if buddy {
            if block.size == length { return "kept" }
            _ = halve(index, length)
            return "shrunk"
        }
        if block.size - length < minBlock { return "kept" }
        blocks.insert(Block(block.start + length, block.size - length), at: index + 1)
        block.size = length
        _ = coalesce(index + 1)
        return "shrunk"
    }
    func growIntoNext(_ index: Int, _ length: Int) -> String? {
        let block = blocks[index]
        if index + 1 >= blocks.count || blocks[index + 1].used { return nil }
        let total = block.size + blocks[index + 1].size
        if total < length { return nil }
        blocks.remove(at: index + 1)
        if total - length >= minBlock {
            block.size = length
            blocks.insert(register(Block(block.end, total - length)), at: index + 1)
        } else {
            block.size = total
        }
        return "grown"
    }
    func growBuddy(_ index: Int, _ length: Int) -> String? {
        let block = blocks[index]
        var extent = block.size, last = index
        while extent < length {
            last += 1
            if block.start % (2 * extent) != 0 || last >= blocks.count { return nil }
            let partner = blocks[last]
            if partner.used || partner.size != extent { return nil }
            extent *= 2
        }
        blocks.removeSubrange((index + 1)...last)
        block.size = length
        return "grown"
    }
    func resize(_ block: Block, _ length: Int) -> String? {
        let index = indexOf(block)
        if length <= block.size { return shrink(index, length) }
        return buddy ? growBuddy(index, length) : growIntoNext(index, length)
    }
    func extend(_ amount: Int) -> Block {
        blocks.append(Block(size, amount))
        size += amount
        return coalesce(blocks.count - 1).0
    }
    func trim() -> Int {
        var released = 0
        if buddy {
            while !blocks.last!.used && 2 * blocks.last!.size == size {
                released += blocks.removeLast().size
                size /= 2
            }
        } else if blocks.count >= 2 && !blocks.last!.used {
            let last = blocks.removeLast()
            released = last.size
            size = last.start
        }
        if rover >= size { rover = 0 }
        return released
    }
    func compact() -> ([Move], Int) {
        var moved: [Move] = []
        var packed = usedBlocks
        var address = 0
        for block in packed {
            if block.start != address {
                moved.append(Move(block: block, from: block.payload))
                block.start = address
            }
            address += block.size
        }
        if address < size { packed.append(register(Block(address, size - address))) }
        blocks = packed
        rover = 0
        return (moved, address)
    }
}

func experiment(_ mode: String, _ size: Int, _ seed: Int, _ operations: Int, _ maxRequest: Int) -> String {
    let heap = Heap(mode, size)
    var state = seed
    var live: [Block] = []
    var used = 0, peak = 0, successes = 0, failures = 0
    for _ in 0..<operations {
        state = nextRandom(state)
        let allocating = live.isEmpty || state % 3 != 0
        state = nextRandom(state)
        if allocating {
            let requested = 1 + state % maxRequest
            if let block = heap.allocate(heap.requiredLength(requested), unit) {
                successes += 1
                live.append(block)
                used += block.size
            } else { failures += 1 }
        } else {
            let block = live.remove(at: state % live.count)
            used -= block.size
            _ = heap.release(block)
        }
        peak = max(peak, used)
    }
    return "BENCH \(mode) ok=\(successes) fail=\(failures) peak=\(peak) " +
           "used=\(used) frag=\(heap.fragmentation) blocks=\(heap.blocks.count)"
}

final class Allocator {
    var heap: Heap?
    var allocations: [String: Block] = [:]
    var freed: Set<String> = []
    var roots: Set<String> = []
    var references: [String: Set<String>] = [:]
    var histories: [String: [String]] = [:]
    var counters: [String: Int] = [:]
    var peak = 0
    var output: [String] = []

    init() { reset(nil) }
    func reset(_ replacement: Heap?) {
        heap = replacement
        allocations = [:]
        freed = []
        roots = []
        references = [:]
        histories = [:]
        counters = Dictionary(uniqueKeysWithValues: counterNames.map { ($0, 0) })
        peak = 0
    }
    func emit(_ parts: Any...) { output.append(parts.map { String(describing: $0) }.joined(separator: " ")) }
    func record(_ id: String, _ line: String) {
        emit(line)
        histories[id, default: []].append(line)
    }
    func increment(_ key: String) { counters[key, default: 0] += 1 }
    func outOfMemory(_ id: String) -> CommandError {
        increment("failures")
        return CommandError("OUT OF MEMORY \(id)")
    }
    func live(_ id: String) throws -> Block {
        if let block = allocations[id] { return block }
        if freed.contains(id) { throw CommandError("USE AFTER FREE \(id)") }
        throw CommandError("UNKNOWN ID \(id)")
    }
    func range(_ id: String, _ offset: Int, _ length: Int) throws -> Block {
        let block = try live(id)
        if offset + length > block.requested { throw CommandError("OUT OF BOUNDS \(id)") }
        return block
    }
    func requireFreeList() throws {
        if heap!.buddy { throw CommandError("UNSUPPORTED IN BUDDY MODE") }
    }
    func reachable() -> Set<String> {
        var found = roots
        var pending = Array(roots)
        while let name = pending.popLast() {
            for target in references[name] ?? [] {
                if found.insert(target).inserted { pending.append(target) }
            }
        }
        return found
    }
    func allocateId(_ command: String, _ id: String, _ request: Int,
                    _ alignment: Int, _ fill: Int) throws {
        if request == 0 { throw CommandError("BAD SIZE") }
        if allocations[id] != nil { throw CommandError("DUPLICATE ID \(id)") }
        guard let block = heap!.allocate(heap!.requiredLength(request), alignment) else {
            throw outOfMemory(id)
        }
        block.owner = id
        block.requested = request
        block.contents = Array(repeating: fill, count: request)
        allocations[id] = block
        freed.remove(id)
        increment("allocs")
        record(id, "\(command) \(id) addr=\(block.payload) block=\(block.size)")
    }
    func releaseId(_ id: String) -> String {
        let block = allocations.removeValue(forKey: id)!
        let size = block.size
        freed.insert(id)
        roots.remove(id)
        references.removeValue(forKey: id)
        for key in references.keys { references[key]!.remove(id) }
        let (result, merges) = heap!.release(block)
        return "block=\(size) merges=\(merges) free=\(result.area)"
    }
    func freeId(_ id: String) throws {
        if freed.contains(id) { throw CommandError("DOUBLE FREE \(id)") }
        if allocations[id] == nil { throw CommandError("UNKNOWN ID \(id)") }
        let details = releaseId(id)
        increment("frees")
        record(id, "FREE \(id) \(details)")
    }
    func reallocId(_ id: String, _ request: Int) throws {
        if request == 0 { try freeId(id); return }
        if freed.contains(id) { throw CommandError("USE AFTER FREE \(id)") }
        guard var block = allocations[id] else {
            try allocateId("MALLOC", id, request, unit, uninitialized)
            return
        }
        let length = heap!.requiredLength(request)
        var contents = Array(block.contents.prefix(request))
        contents += Array(repeating: uninitialized, count: max(0, request - contents.count))
        let original = block.payload
        var kind = heap!.resize(block, length)
        if kind == nil {
            guard let moved = heap!.allocate(length, unit) else { throw outOfMemory(id) }
            moved.owner = id
            allocations[id] = moved
            _ = heap!.release(block)
            increment("moves")
            block = moved
            kind = "moved from=\(original)"
        }
        block.requested = request
        block.contents = contents
        increment("reallocs")
        record(id, "REALLOC \(id) addr=\(block.payload) block=\(block.size) \(kind!)")
    }
    func treeNode(_ leaves: [Int: Block], _ start: Int, _ size: Int, _ depth: Int) {
        let label = String(repeating: " ", count: depth * 2) + "\(start)+\(size)"
        if let block = leaves[start], block.size == size {
            emit(label + (block.used ? " USED \(block.owner!)" : " FREE"))
            return
        }
        emit(label + " split")
        treeNode(leaves, start, size / 2, depth + 1)
        treeNode(leaves, start + size / 2, size / 2, depth + 1)
    }
    func run(_ command: String, _ a: [String]) throws {
        if command == "HEAP" {
            let size = Int(a[0])!, mode = a[1]
            if size < 32 || size > maxHeap || size % unit != 0 ||
                (mode == "BUDDY" && !isPowerOfTwo(size)) {
                throw CommandError("BAD HEAP SIZE")
            }
            reset(Heap(mode, size))
            emit("HEAP size=\(size) mode=\(mode)")
            return
        }
        if command == "BENCH" {
            let size = Int(a[0])!, seed = Int(a[1])!, operations = Int(a[2])!, maxRequest = Int(a[3])!
            if size < 32 || size > maxHeap || !isPowerOfTwo(size) {
                throw CommandError("BAD HEAP SIZE")
            }
            emit("BENCH heap=\(size) seed=\(seed) ops=\(operations) maxreq=\(maxRequest)")
            for mode in modes { emit(experiment(mode, size, seed, operations, maxRequest)) }
            return
        }
        let heap = self.heap!
        switch command {
        case "MALLOC":
            try allocateId("MALLOC", a[0], Int(a[1])!, unit, uninitialized)
        case "CALLOC":
            try allocateId("CALLOC", a[0], Int(a[1])! * Int(a[2])!, unit, 0)
        case "MEMALIGN":
            try requireFreeList()
            let alignment = Int(a[1])!
            if !isPowerOfTwo(alignment) || alignment < unit || alignment > 4096 {
                throw CommandError("BAD ALIGNMENT")
            }
            try allocateId("MEMALIGN", a[0], Int(a[2])!, alignment, uninitialized)
        case "REALLOC":
            try reallocId(a[0], Int(a[1])!)
        case "FREE":
            try freeId(a[0])
        case "FILL":
            let id = a[0], offset = Int(a[1])!, length = Int(a[2])!, value = Int(a[3])!
            let block = try range(id, offset, length)
            for i in offset..<(offset + length) { block.contents[i] = value }
            emit("FILL \(id) \(offset)+\(length) = \(value)")
        case "COPY":
            let dest = a[0], doff = Int(a[1])!, source = a[2]
            let soff = Int(a[3])!, length = Int(a[4])!
            let dst = try range(dest, doff, length)
            let src = try range(source, soff, length)
            let saved = Array(src.contents[soff..<(soff + length)])
            dst.contents.replaceSubrange(doff..<(doff + length), with: saved)
            emit("COPY \(dest) \(doff)+\(length) from \(source) \(soff)")
        case "READ":
            let id = a[0], offset = Int(a[1])!, length = Int(a[2])!
            let block = try range(id, offset, length)
            let values = block.contents[offset..<(offset + length)].map {
                $0 == uninitialized ? "?" : String($0)
            }.joined(separator: " ")
            emit("READ \(id) \(offset)+\(length) = \(values)")
        case "ROOT":
            _ = try live(a[0])
            roots.insert(a[0])
            emit("ROOT \(a[0])")
        case "UNROOT":
            _ = try live(a[0])
            if !roots.contains(a[0]) { throw CommandError("NOT ROOT \(a[0])") }
            roots.remove(a[0])
            emit("UNROOT \(a[0])")
        case "LINK":
            _ = try live(a[0]); _ = try live(a[1])
            references[a[0], default: []].insert(a[1])
            emit("LINK \(a[0]) \(a[1])")
        case "UNLINK":
            _ = try live(a[0]); _ = try live(a[1])
            if !(references[a[0]]?.contains(a[1]) ?? false) {
                throw CommandError("NO LINK \(a[0]) \(a[1])")
            }
            references[a[0]]!.remove(a[1])
            emit("UNLINK \(a[0]) \(a[1])")
        case "GC":
            let found = reachable()
            let garbage = allocations.filter { !found.contains($0.key) }
                .map { $0.value }.sorted { $0.start < $1.start }
            emit("GC collected=\(garbage.count) bytes=\(garbage.reduce(0) { $0 + $1.size })")
            for block in garbage {
                let id = block.owner!
                record(id, "COLLECT \(id) \(releaseId(id))")
            }
            counters["collected", default: 0] += garbage.count
        case "SBRK":
            let amount = Int(a[0])!
            let valid = heap.buddy
                ? amount == heap.size && 2 * heap.size <= maxHeap
                : amount % unit == 0 && amount >= minBlock && heap.size + amount <= maxHeap
            if !valid { throw CommandError("BAD SBRK SIZE") }
            let block = heap.extend(amount)
            emit("SBRK heap=\(heap.size) free=\(block.area)")
        case "TRIM":
            let released = heap.trim()
            emit("TRIM heap=\(heap.size) released=\(released)")
        case "COMPACT":
            try requireFreeList()
            let (moved, used) = heap.compact()
            counters["moves", default: 0] += moved.count
            let free = used < heap.size ? "\(used)+\(heap.size - used)" : "none"
            emit("COMPACT moved=\(moved.count) free=\(free)")
            for step in moved {
                let id = step.block.owner!
                record(id, "MOVE \(id) \(step.from) -> \(step.block.payload)")
            }
        case "WHO":
            let address = Int(a[0])!
            if address >= heap.size { emit("WHO \(address) outside") }
            else {
                let block = heap.blocks[heap.locate(address)]
                if !block.used { emit("WHO \(address) free \(block.area)") }
                else if address < block.payload { emit("WHO \(address) header \(block.owner!)") }
                else {
                    let offset = address - block.payload
                    emit("WHO \(address) \(offset < block.requested ? "data" : "slack") \(block.owner!)+\(offset)")
                }
            }
        case "DUMP":
            let rover = heap.mode == "NEXT" ? " rover=\(heap.rover)" : ""
            emit("DUMP mode=\(heap.mode) heap=\(heap.size) blocks=\(heap.blocks.count)\(rover)")
            for block in heap.blocks {
                if block.used {
                    emit("\(block.start) \(block.size) USED \(block.owner!) req=\(block.requested)")
                } else { emit("\(block.start) \(block.size) FREE") }
            }
        case "MAP":
            emit("MAP heap=\(heap.size)")
            let units = heap.blocks.map(\.mapUnits).joined()
            let chars = Array(units)
            for first in stride(from: 0, to: chars.count, by: 64) {
                let label = String(format: "%05d", first * unit)
                emit("\(label) \(String(chars[first..<min(first + 64, chars.count)]))")
            }
        case "FREELIST":
            var free = heap.freeBlocks
            if heap.mode == "SEGFIT" { free.sort { $0.stamp > $1.stamp } }
            emit("FREELIST count=\(free.count)")
            var groups: [Int: [String]] = [:]
            for block in free { groups[sizeClass(block.size), default: []].append(block.area) }
            for exponent in groups.keys.sorted() {
                let values = groups[exponent]!.joined(separator: " ")
                emit("\(1 << exponent)-\((1 << (exponent + 1)) - 1): \(values)")
            }
        case "TREE":
            if !heap.buddy { throw CommandError("REQUIRES BUDDY MODE") }
            emit("TREE heap=\(heap.size)")
            let leaves = Dictionary(uniqueKeysWithValues: heap.blocks.map { ($0.start, $0) })
            treeNode(leaves, 0, heap.size, 0)
        case "STATS":
            let used = heap.usedBlocks, free = heap.freeBlocks
            let totalFree = free.reduce(0) { $0 + $1.size }
            let largest = free.map(\.size).max() ?? 0
            let totalUsed = used.reduce(0) { $0 + $1.size }
            let requested = used.reduce(0) { $0 + $1.requested }
            emit("STATS used=\(totalUsed) used_blocks=\(used.count) free=\(totalFree) " +
                 "free_blocks=\(free.count) largest=\(largest) " +
                 "frag=\(fragmentationPercent(totalFree, largest)) requested=\(requested) peak=\(peak)")
            let counts = counterNames.map { "\($0)=\(counters[$0, default: 0])" }.joined(separator: " ")
            emit("OPS \(counts)")
        case "LEAKS":
            let found = reachable()
            let names = allocations.keys.sorted()
            let requested = names.reduce(0) { $0 + allocations[$1]!.requested }
            let lost = names.filter { !found.contains($0) }.count
            emit("LEAKS count=\(names.count) requested=\(requested) lost=\(lost)")
            for id in names {
                let block = allocations[id]!
                emit("LEAK \(id) addr=\(block.payload) block=\(block.size) " +
                     "req=\(block.requested) \(found.contains(id) ? "reachable" : "lost")")
            }
        case "HISTORY":
            let lines = histories[a[0]] ?? []
            emit("HISTORY \(a[0]) events=\(lines.count)")
            output.append(contentsOf: lines)
        default:
            fatalError("Unexpected command \(command)")
        }
    }
    func execute(_ commandLine: String) {
        let tokens = commandLine.split(separator: " ").map(String.init)
        let command = tokens[0]
        let args = Array(tokens.dropFirst())
        do {
            if heap == nil && command != "HEAP" && command != "BENCH" {
                throw CommandError("NO HEAP")
            }
            try run(command, args)
        } catch let error as CommandError {
            emit("ERROR \(error.message)")
        } catch { fatalError("Unexpected error: \(error)") }
        if let heap { peak = max(peak, heap.usedTotal) }
    }
}

let commandCount = Int(readLine()!)!
let allocator = Allocator()
for _ in 0..<commandCount { allocator.execute(readLine()!) }
print(allocator.output.joined(separator: "\n"))

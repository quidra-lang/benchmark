import Foundation

enum CommandError: Error {
    case reason(String)
}

func fail(_ reason: String) throws -> Never {
    throw CommandError.reason(reason)
}

func ceiling(_ numerator: Int, _ denominator: Int) -> Int {
    (numerator + denominator - 1) / denominator
}

struct Item: CustomStringConvertible {
    let number: Int
    let size: Int

    var description: String { "\(number):\(size)" }
}

func descending(_ items: [Item]) -> [Item] {
    items.sorted {
        $0.size == $1.size ? $0.number < $1.number : $0.size > $1.size
    }
}

final class Bin {
    var items: [Item] = []
    var load = 0
    let category: Int

    init(category: Int = 0) {
        self.category = category
    }

    func put(_ item: Item) {
        items.append(item)
        load += item.size
    }

    func copy() -> Bin {
        let result = Bin(category: category)
        result.items = items
        result.load = load
        return result
    }
}

struct Step {
    let item: Item
    let bin: Int
    let inspected: Int
    let opened: Bool
    let closed: Int
    let category: Int
}

final class Packing {
    let method: String
    let parameter: Int
    var bins: [Bin] = []
    var steps: [Step] = []
    var inspections = 0
    var closes = 0

    init(_ method: String, _ parameter: Int = 0) {
        self.method = method
        self.parameter = parameter
    }

    var name: String {
        method == "HARMONIC" || method == "KBOUNDED"
            ? "\(method) k=\(parameter)" : method
    }

    func header(_ capacity: Int, _ total: Int) -> String {
        var line = "\(name) bins=\(bins.count) inspections=\(inspections) " +
            "waste=\(bins.count * capacity - total)"
        if method == "KBOUNDED" {
            line += " closes=\(closes)"
        }
        return line
    }
}

func pack(_ items: [Item], _ capacity: Int, _ method: String,
          _ parameter: Int = 0) -> Packing {
    let result = Packing(method, parameter)
    let order = ["FFD", "BFD", "WFD"].contains(method) ? descending(items) : items
    var active: [Int] = []
    var current: [Int: Int] = [:]

    for item in order {
        let before = result.inspections
        var chosen = -1
        var closed = -1
        var category = 0
        switch method {
        case "NEXTFIT":
            if !result.bins.isEmpty {
                result.inspections += 1
                let last = result.bins.count - 1
                if result.bins[last].load + item.size <= capacity {
                    chosen = last
                }
            }
        case "FIRSTFIT", "FFD", "KBOUNDED":
            let candidates = method == "KBOUNDED"
                ? active : Array(result.bins.indices)
            for index in candidates {
                result.inspections += 1
                if result.bins[index].load + item.size <= capacity {
                    chosen = index
                    break
                }
            }
        case "HARMONIC":
            category = min(capacity / item.size, parameter)
            if let index = current[category] {
                result.inspections += 1
                if result.bins[index].load + item.size <= capacity {
                    chosen = index
                }
            }
        default:
            result.inspections += result.bins.count
            let fitting = result.bins.indices.filter {
                result.bins[$0].load + item.size <= capacity
            }
            if !fitting.isEmpty {
                if method == "BESTFIT" || method == "BFD" {
                    chosen = fitting[0]
                    for index in fitting {
                        if result.bins[index].load > result.bins[chosen].load {
                            chosen = index
                        }
                    }
                } else {
                    let sorted = fitting.sorted {
                        result.bins[$0].load == result.bins[$1].load
                            ? $0 < $1 : result.bins[$0].load < result.bins[$1].load
                    }
                    chosen = method == "ALMOSTWORST" && sorted.count >= 2
                        ? sorted[1] : sorted[0]
                }
            }
        }

        let opened = chosen < 0
        if opened {
            if method == "KBOUNDED" && active.count == parameter {
                closed = active[0]
                for index in active {
                    if result.bins[index].load > result.bins[closed].load {
                        closed = index
                    }
                }
                active.removeAll { $0 == closed }
                result.closes += 1
            }
            chosen = result.bins.count
            result.bins.append(Bin(category: category))
            if method == "KBOUNDED" { active.append(chosen) }
            if method == "HARMONIC" { current[category] = chosen }
        }
        result.bins[chosen].put(item)
        result.steps.append(Step(item: item, bin: chosen,
                                 inspected: result.inspections - before,
                                 opened: opened, closed: closed, category: category))
    }
    return result
}

struct BoundRow {
    let alpha: Int
    let j1: Int
    let j2: Int
    let j3: Int
    let bound: Int
}

struct Bounds {
    let l1: Int
    let l2: Int
    let rows: [BoundRow]
}

func lowerBounds(_ items: [Item], _ capacity: Int) -> Bounds {
    let total = items.reduce(0) { $0 + $1.size }
    var thresholds: Set<Int> = [0]
    for item in items where item.size * 2 <= capacity {
        thresholds.insert(item.size)
    }
    var rows: [BoundRow] = []
    var lower = 0
    for alpha in thresholds.sorted() {
        var j1 = 0, j2 = 0, j3 = 0, sum2 = 0, sum3 = 0
        for item in items {
            let size = item.size
            if size > capacity - alpha {
                j1 += 1
            } else if 2 * size > capacity {
                j2 += 1
                sum2 += size
            } else if size >= alpha {
                j3 += 1
                sum3 += size
            }
        }
        let excess = sum3 - (j2 * capacity - sum2)
        let bound = j1 + j2 + (excess > 0 ? ceiling(excess, capacity) : 0)
        lower = max(lower, bound)
        rows.append(BoundRow(alpha: alpha, j1: j1, j2: j2, j3: j3,
                             bound: bound))
    }
    return Bounds(l1: ceiling(total, capacity), l2: lower, rows: rows)
}

final class ExactSearch {
    let order: [Item]
    let capacity: Int
    let limit: Int
    let lower: Int
    let emit: (String) -> Void
    let remaining: [Int]
    var best: [Bin]
    var live: [Bin] = []
    var nodes = 0
    var status: String?

    init(_ items: [Item], _ capacity: Int, _ limit: Int, _ lower: Int,
         _ incumbent: [Bin], _ emit: @escaping (String) -> Void) {
        order = descending(items)
        self.capacity = capacity
        self.limit = limit
        self.lower = lower
        self.emit = emit
        best = incumbent.map { $0.copy() }
        var suffix = Array(repeating: 0, count: order.count + 1)
        for index in order.indices.reversed() {
            suffix[index] = suffix[index + 1] + order[index].size
        }
        remaining = suffix
    }

    func visit(_ index: Int) {
        if nodes == limit {
            status = "limit"
            return
        }
        nodes += 1
        let count = live.count
        let used = remaining[0] - remaining[index]
        let free = count * capacity - used
        let excess = remaining[index] - free
        let minimum = count + (excess > 0 ? ceiling(excess, capacity) : 0)
        if minimum >= best.count { return }

        if index == order.count {
            best = live.map { $0.copy() }
            emit("IMPROVE bins=\(count) nodes=\(nodes)")
            if count == lower { status = "bound" }
            return
        }
        let item = order[index]
        var seen: Set<Int> = []
        for bin in live {
            let old = bin.load
            if seen.contains(old) || old + item.size > capacity { continue }
            seen.insert(old)
            bin.put(item)
            visit(index + 1)
            bin.items.removeLast()
            bin.load = old
            if status != nil { return }
        }
        if count + 1 < best.count {
            let bin = Bin()
            bin.put(item)
            live.append(bin)
            visit(index + 1)
            live.removeLast()
        }
    }
}

struct Rect {
    let number: Int
    let width: Int
    let height: Int

    var letter: Character {
        Character(UnicodeScalar(64 + number)!)
    }
    var area: Int { width * height }
}

struct Placement {
    let rect: Rect
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let rotated: Bool
}

final class Shelf {
    let bottom: Int
    let height: Int
    var used = 0
    var placements: [Placement] = []

    init(_ bottom: Int, _ height: Int) {
        self.bottom = bottom
        self.height = height
    }
}

struct FreeRect: CustomStringConvertible {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    var area: Int { width * height }
    var description: String { "\(x),\(y),\(width)x\(height)" }
}

final class Sheet {
    var free: [FreeRect]
    var placements: [Placement] = []
    var area = 0

    init(_ width: Int, _ height: Int) {
        free = [FreeRect(x: 0, y: 0, width: width, height: height)]
    }
}

struct Piece {
    let length: Int
    let demand: Int
}

struct Pattern {
    let counts: [Int]
    let trim: Int
}

final class Lab {
    var items: [Item]?
    var capacity = 0
    var output: [String] = []
    let methods = ["NEXTFIT", "FIRSTFIT", "BESTFIT", "WORSTFIT", "ALMOSTWORST",
                   "HARMONIC", "KBOUNDED", "FFD", "BFD", "WFD"]

    func emit(_ line: String) { output.append(line) }

    var total: Int { items!.reduce(0) { $0 + $1.size } }

    func parameter(_ method: String, _ words: [String], _ index: Int) throws -> Int {
        guard method == "HARMONIC" || method == "KBOUNDED" else { return 0 }
        let value = Int(words[index])!
        if value == 0 { try fail("BAD PARAMETER") }
        return value
    }

    func binLine(_ number: Int, _ bin: Bin, _ cap: Int,
                 _ showClass: Bool = false, _ over: Bool = false) {
        var line = "BIN \(number) load=\(bin.load)/\(cap) items=" +
            bin.items.map(\.description).joined(separator: " ")
        if showClass { line += " class=\(bin.category)" }
        if over { line += " OVER" }
        emit(line)
    }

    func binLines(_ bins: [Bin], _ showClass: Bool = false) {
        for (index, bin) in bins.enumerated() {
            binLine(index + 1, bin, capacity, showClass)
        }
    }

    func itemsCommand(_ words: [String]) throws {
        let cap = Int(words[1])!
        if cap == 0 { try fail("BAD CAPACITY") }
        var next: [Item] = []
        for (index, text) in words.dropFirst(2).enumerated() {
            let size = Int(text)!
            if size == 0 || size > cap { try fail("BAD ITEM \(index + 1)") }
            next.append(Item(number: index + 1, size: size))
        }
        items = next
        capacity = cap
        emit("ITEMS count=\(next.count) capacity=\(cap) total=\(total)")
    }

    func random(_ words: [String]) throws {
        let count = Int(words[1])!
        let cap = Int(words[2])!
        var seed = Int(words[3])!
        if count == 0 || count > 40 { try fail("BAD COUNT") }
        if cap == 0 { try fail("BAD CAPACITY") }
        if seed == 0 || seed >= 2_147_483_647 { try fail("BAD SEED") }
        var next: [Item] = []
        for number in 1...count {
            seed = 48_271 * seed % 2_147_483_647
            next.append(Item(number: number, size: seed % cap + 1))
        }
        items = next
        capacity = cap
        emit("RANDOM count=\(count) capacity=\(cap) total=\(total)")
        emit("SIZES " + next.map { String($0.size) }.joined(separator: " "))
    }

    func method(_ name: String, _ k: Int) {
        let result = pack(items!, capacity, name, k)
        emit(result.header(capacity, total))
        binLines(result.bins, name == "HARMONIC")
    }

    func trace(_ name: String, _ k: Int) {
        let result = pack(items!, capacity, name, k)
        emit("TRACE " + result.header(capacity, total))
        for (index, step) in result.steps.enumerated() {
            var line = "STEP \(index + 1) item=\(step.item) bin=\(step.bin + 1) " +
                "inspected=\(step.inspected)"
            if step.opened { line += " new" }
            if step.closed >= 0 { line += " closed=\(step.closed + 1)" }
            if name == "HARMONIC" { line += " class=\(step.category)" }
            emit(line)
        }
    }

    func reduce(_ name: String, _ k: Int) {
        let result = pack(items!, capacity, name, k)
        var bins = result.bins
        let before = bins.count
        var events: [String] = []
        while true {
            var eliminated = false
            let sources = bins.indices.sorted {
                bins[$0].load == bins[$1].load
                    ? $0 < $1 : bins[$0].load < bins[$1].load
            }
            for source in sources {
                var loads = bins.map(\.load)
                var moves: [(Item, Int)] = []
                var possible = true
                for item in descending(bins[source].items) {
                    var destination = -1
                    for index in bins.indices {
                        if index == source || loads[index] + item.size > capacity {
                            continue
                        }
                        if destination < 0 || loads[index] > loads[destination] {
                            destination = index
                        }
                    }
                    if destination < 0 {
                        possible = false
                        break
                    }
                    loads[destination] += item.size
                    moves.append((item, destination))
                }
                if !possible { continue }
                let descriptions = moves.map {
                    "\($0.0)->\($0.1 + 1)"
                }.joined(separator: " ")
                events.append("ELIMINATE bin=\(source + 1) load=\(bins[source].load) moves=\(descriptions)")
                for (item, destination) in moves { bins[destination].put(item) }
                bins.remove(at: source)
                eliminated = true
                break
            }
            if !eliminated { break }
        }
        emit("REDUCE \(result.name) before=\(before) after=\(bins.count) " +
            "eliminated=\(before - bins.count)")
        for event in events { emit(event) }
        binLines(bins, name == "HARMONIC")
    }

    func boundsCommand() {
        let result = lowerBounds(items!, capacity)
        emit("BOUNDS total=\(total) L1=\(result.l1) L2=\(result.l2)")
        for row in result.rows {
            emit("ALPHA \(row.alpha) j1=\(row.j1) j2=\(row.j2) " +
                "j3=\(row.j3) bound=\(row.bound)")
        }
    }

    func compare(_ k: Int) throws {
        if k == 0 { try fail("BAD PARAMETER") }
        let bounds = lowerBounds(items!, capacity)
        let results = methods.map { pack(items!, capacity, $0, k) }.sorted {
            $0.bins.count == $1.bins.count
                ? $0.method < $1.method : $0.bins.count < $1.bins.count
        }
        emit("COMPARE k=\(k) L1=\(bounds.l1) L2=\(bounds.l2)")
        for p in results {
            let count = p.bins.count
            emit("\(p.method) bins=\(count) gap=\(count - bounds.l2) " +
                "waste=\(count * capacity - total) inspections=\(p.inspections)")
        }
    }

    func exact(_ limit: Int) throws {
        if limit == 0 { try fail("BAD PARAMETER") }
        if items!.count >= 21 { try fail("TOO MANY ITEMS") }
        let incumbent = pack(items!, capacity, "FFD").bins
        let lower = lowerBounds(items!, capacity).l2
        emit("EXACT ffd=\(incumbent.count) L2=\(lower)")
        let search = ExactSearch(items!, capacity, limit, lower, incumbent) {
            self.emit($0)
        }
        if incumbent.count == lower { search.status = "bound" }
        else { search.visit(0) }
        emit("RESULT bins=\(search.best.count) nodes=\(search.nodes) " +
            "status=\(search.status ?? "complete")")
        binLines(search.best)
    }

    func check(_ words: [String]) throws {
        if words.count - 1 != items!.count { try fail("BAD ASSIGNMENT") }
        let labels = words.dropFirst().map { Int($0)! }
        if labels.contains(0) { try fail("BAD ASSIGNMENT") }
        var bins: [Int: Bin] = [:]
        for (index, item) in items!.enumerated() {
            let label = labels[index]
            if bins[label] == nil { bins[label] = Bin() }
            bins[label]!.put(item)
        }
        let over = bins.values.filter { $0.load > capacity }.count
        let lower = lowerBounds(items!, capacity).l2
        emit("CHECK bins=\(bins.count) over=\(over) L2=\(lower) " +
            "status=\(over == 0 ? "valid" : "invalid")")
        for label in bins.keys.sorted() {
            let bin = bins[label]!
            binLine(label, bin, capacity, false, bin.load > capacity)
        }
    }

    func coverLines(_ name: String, _ bins: [Bin]) {
        let covered = bins.filter { $0.load >= capacity }
        let rest = bins.first { $0.load < capacity }
        emit("\(name) covered=\(covered.count) rest=\(rest?.load ?? 0)")
        binLines(covered)
        if let rest {
            emit("REST items=" + rest.items.map(\.description).joined(separator: " "))
        }
    }

    func cover() {
        emit("COVER total=\(total) upper=\(total / capacity)")
        var sequential: [Bin] = []
        for item in items! {
            if sequential.isEmpty || sequential.last!.load >= capacity {
                sequential.append(Bin())
            }
            sequential.last!.put(item)
        }
        coverLines("DNF", sequential)

        let ordered = descending(items!)
        var paired: [Bin] = []
        var first = 0
        var last = ordered.count - 1
        while first <= last {
            let bin = Bin()
            bin.put(ordered[first])
            first += 1
            while bin.load < capacity && first <= last {
                bin.put(ordered[last])
                last -= 1
            }
            paired.append(bin)
        }
        coverLines("BIGSMALL", paired)
    }

    func machineLines(_ bins: [Bin]) {
        for (index, bin) in bins.enumerated() {
            let description = bin.items.isEmpty ? "-" :
                bin.items.map(\.description).joined(separator: " ")
            emit("MACHINE \(index + 1) load=\(bin.load) items=\(description)")
        }
    }

    func multifit(_ count: Int) throws {
        if count == 0 { try fail("BAD PARAMETER") }
        let largest = items!.map(\.size).max()!
        var low = max(ceiling(total, count), largest)
        var high = max(ceiling(2 * total, count), largest)
        emit("MULTIFIT m=\(count) lower=\(low) upper=\(high)")
        while low < high {
            let middle = low + (high - low) / 2
            let bins = pack(items!, middle, "FFD").bins.count
            let ok = bins <= count
            emit("TRY cap=\(middle) bins=\(bins) \(ok ? "ok" : "fail")")
            if ok { high = middle } else { low = middle + 1 }
        }
        var machines = pack(items!, high, "FFD").bins
        while machines.count < count { machines.append(Bin()) }
        emit("RESULT cap=\(high) makespan=\(machines.map(\.load).max()!)")
        machineLines(machines)

        let lpt = (0..<count).map { _ in Bin() }
        for item in descending(items!) {
            let target = lpt.indices.min {
                lpt[$0].load == lpt[$1].load
                    ? $0 < $1 : lpt[$0].load < lpt[$1].load
            }!
            lpt[target].put(item)
        }
        emit("LPT makespan=\(lpt.map(\.load).max()!)")
        machineLines(lpt)
    }

    func cutstock(_ words: [String]) throws {
        let length = Int(words[1])!
        if length == 0 { try fail("BAD CAPACITY") }
        var pieces: [Piece] = []
        var seen: Set<Int> = []
        for (index, word) in words.dropFirst(2).enumerated() {
            let parts = word.split(separator: ":").map(String.init)
            let size = Int(parts[0])!
            let demand = Int(parts[1])!
            if size == 0 || size > length || demand == 0 {
                try fail("BAD PIECE \(index + 1)")
            }
            if seen.contains(size) { try fail("DUPLICATE PIECE \(index + 1)") }
            seen.insert(size)
            pieces.append(Piece(length: size, demand: demand))
        }
        pieces.sort { $0.length > $1.length }

        var patterns: [Pattern] = []
        var counts = Array(repeating: 0, count: pieces.count)
        func enumerate(_ index: Int, _ remaining: Int) {
            let maximum = remaining / pieces[index].length
            if index == pieces.count - 1 {
                counts[index] = maximum
                patterns.append(Pattern(counts: counts,
                    trim: remaining - maximum * pieces[index].length))
                return
            }
            for c in stride(from: maximum, through: 0, by: -1) {
                counts[index] = c
                enumerate(index + 1, remaining - c * pieces[index].length)
            }
        }
        enumerate(0, length)
        emit("CUTSTOCK L=\(length) pieces=\(pieces.count) patterns=\(patterns.count)")
        for (index, pattern) in patterns.enumerated() {
            var breakdown: [String] = []
            for i in pieces.indices where pattern.counts[i] > 0 {
                breakdown.append("\(pattern.counts[i])x\(pieces[i].length)")
            }
            emit("PATTERN \(index + 1) \(breakdown.joined(separator: "+")) rest=\(pattern.trim)")
        }

        var remaining = pieces.map(\.demand)
        var cut = Array(repeating: 0, count: pieces.count)
        var used = Array(repeating: 0, count: patterns.count)
        while remaining.contains(where: { $0 > 0 }) {
            var chosen = 0, highest = -1
            for (index, pattern) in patterns.enumerated() {
                var useful = 0
                for i in pieces.indices {
                    useful += min(pattern.counts[i], remaining[i])
                }
                if useful > highest {
                    chosen = index
                    highest = useful
                }
            }
            used[chosen] += 1
            for i in pieces.indices {
                let count = patterns[chosen].counts[i]
                cut[i] += count
                remaining[i] = max(0, remaining[i] - count)
            }
        }
        var bars = 0, trim = 0
        for i in patterns.indices where used[i] > 0 {
            emit("USE \(i + 1) bars=\(used[i])")
            bars += used[i]
            trim += used[i] * patterns[i].trim
        }
        var quantity = 0, cutTotal = 0, demandTotal = 0
        var stock: [Item] = []
        for (i, piece) in pieces.enumerated() {
            quantity += piece.length * piece.demand
            cutTotal += cut[i]
            demandTotal += piece.demand
            emit("PIECE \(piece.length) demand=\(piece.demand) cut=\(cut[i])")
            for _ in 0..<piece.demand {
                stock.append(Item(number: stock.count + 1, size: piece.length))
            }
        }
        emit("TOTAL bars=\(bars) trim=\(trim) surplus=\(cutTotal - demandTotal) " +
            "waste=\(bars * length - quantity)")
        let ffd = pack(stock, length, "FIRSTFIT").bins.count
        emit("FFD bars=\(ffd) waste=\(ffd * length - quantity)")
        emit("LOWER bars=\(ceiling(quantity, length))")
    }

    func rectangles(_ words: [String], _ start: Int, _ width: Int,
                    _ height: Int, _ rotate: Bool) throws -> [Rect] {
        var result: [Rect] = []
        for (index, word) in words.dropFirst(start).enumerated() {
            let pair = word.split(separator: "x").map(String.init)
            let w = Int(pair[0])!, h = Int(pair[1])!
            let fits = height == 0 ? w <= width :
                ((w <= width && h <= height) || (rotate && h <= width && w <= height))
            if w == 0 || h == 0 || !fits {
                try fail("BAD RECT \(index + 1)")
            }
            result.append(Rect(number: index + 1, width: w, height: h))
        }
        return result
    }

    func draw(_ width: Int, _ height: Int, _ placements: [Placement]) {
        var grid = Array(repeating: Array(repeating: Character("."),
            count: width), count: height)
        for placement in placements {
            for y in placement.y..<(placement.y + placement.height) {
                for x in placement.x..<(placement.x + placement.width) {
                    grid[y][x] = placement.rect.letter
                }
            }
        }
        for y in stride(from: height - 1, through: 0, by: -1) {
            emit(String(grid[y]))
        }
    }

    func shelf(_ words: [String]) throws {
        let width = Int(words[1])!
        if width == 0 { try fail("BAD CAPACITY") }
        let source = try rectangles(words, 2, width, 0, false)
        let area = source.reduce(0) { $0 + $1.area }
        emit("SHELF W=\(width) rects=\(source.count) area=\(area)")
        let order = source.sorted {
            if $0.height != $1.height { return $0.height > $1.height }
            if $0.width != $1.width { return $0.width > $1.width }
            return $0.number < $1.number
        }
        for method in ["NFDH", "FFDH", "BFDH"] {
            var shelves: [Shelf] = []
            var placements: [Placement] = []
            for rect in order {
                var chosen: Shelf?
                if method == "NFDH" {
                    if let last = shelves.last, last.used + rect.width <= width {
                        chosen = last
                    }
                } else {
                    for shelf in shelves where shelf.used + rect.width <= width {
                        if chosen == nil || (method == "BFDH" &&
                                            shelf.used > chosen!.used) {
                            chosen = shelf
                        }
                        if method == "FFDH" { break }
                    }
                }
                if chosen == nil {
                    let bottom = shelves.isEmpty ? 0 :
                        shelves.last!.bottom + shelves.last!.height
                    chosen = Shelf(bottom, rect.height)
                    shelves.append(chosen!)
                }
                let shelf = chosen!
                let p = Placement(rect: rect, x: shelf.used, y: shelf.bottom,
                                  width: rect.width, height: rect.height, rotated: false)
                shelf.placements.append(p)
                placements.append(p)
                shelf.used += rect.width
            }
            let height = shelves.last!.bottom + shelves.last!.height
            emit("\(method) height=\(height) shelves=\(shelves.count) " +
                "util=\(area * 100 / (width * height))")
            for (i, shelf) in shelves.enumerated() {
                let names = shelf.placements.map {
                    "\($0.rect.letter)@\($0.x)"
                }.joined(separator: " ")
                emit("LEVEL \(i + 1) y=\(shelf.bottom) h=\(shelf.height) " +
                    "used=\(shelf.used) items=\(names)")
            }
            draw(width, height, placements)
        }

        var columns = Array(repeating: 0, count: width)
        var skyline: [Placement] = []
        for rect in order {
            var bestX = 0, bestY = Int.max
            for x in 0...(width - rect.width) {
                let y = columns[x..<(x + rect.width)].max()!
                if y < bestY {
                    bestX = x
                    bestY = y
                }
            }
            skyline.append(Placement(rect: rect, x: bestX, y: bestY,
                width: rect.width, height: rect.height, rotated: false))
            for x in bestX..<(bestX + rect.width) {
                columns[x] = bestY + rect.height
            }
        }
        let height = columns.max()!
        emit("SKYLINE height=\(height) util=\(area * 100 / (width * height))")
        for p in skyline {
            emit("PLACE \(p.rect.letter) x=\(p.x) y=\(p.y) w=\(p.width) h=\(p.height)")
        }
        draw(width, height, skyline)
    }

    func fits(_ rect: Rect, _ free: FreeRect, _ rotate: Bool) -> Bool {
        (rect.width <= free.width && rect.height <= free.height) ||
            (rotate && rect.height <= free.width && rect.width <= free.height)
    }

    func guillotine(_ words: [String]) throws {
        let width = Int(words[1])!, height = Int(words[2])!
        if width == 0 || height == 0 { try fail("BAD CAPACITY") }
        let rotate = words[3] == "ROTATE"
        let best = words[4] == "BEST"
        let order = try rectangles(words, 5, width, height, rotate).sorted {
            $0.area == $1.area ? $0.number < $1.number : $0.area > $1.area
        }
        let area = order.reduce(0) { $0 + $1.area }
        var sheets: [Sheet] = []
        var rotated = 0

        for rect in order {
            var selected: Sheet?
            var selectedIndex = -1, selectedArea = Int.max
            for sheet in sheets {
                for (index, free) in sheet.free.enumerated() {
                    if !fits(rect, free, rotate) { continue }
                    if selected == nil || (best && free.area < selectedArea) {
                        selected = sheet
                        selectedIndex = index
                        selectedArea = free.area
                    }
                    if !best { break }
                }
                if selected != nil && !best { break }
            }
            if selected == nil {
                selected = Sheet(width, height)
                sheets.append(selected!)
                selectedIndex = 0
            }
            let sheet = selected!
            let target = sheet.free.remove(at: selectedIndex)
            let turned = rect.width > target.width || rect.height > target.height
            let w = turned ? rect.height : rect.width
            let h = turned ? rect.width : rect.height
            if turned { rotated += 1 }
            sheet.placements.append(Placement(rect: rect, x: target.x, y: target.y,
                                              width: w, height: h, rotated: turned))
            sheet.area += rect.area
            let rw = target.width - w, rh = target.height - h
            let top = rw <= rh
                ? FreeRect(x: target.x, y: target.y + h, width: target.width, height: rh)
                : FreeRect(x: target.x, y: target.y + h, width: w, height: rh)
            let right = rw <= rh
                ? FreeRect(x: target.x + w, y: target.y, width: rw, height: h)
                : FreeRect(x: target.x + w, y: target.y, width: rw, height: target.height)
            if top.width > 0 && top.height > 0 { sheet.free.append(top) }
            if right.width > 0 && right.height > 0 { sheet.free.append(right) }
        }
        emit("GUILLOTINE W=\(width) H=\(height) mode=\(words[3]) rule=\(words[4]) " +
            "rects=\(order.count) sheets=\(sheets.count) rotated=\(rotated) " +
            "util=\(area * 100 / (sheets.count * width * height))")
        for (index, sheet) in sheets.enumerated() {
            emit("SHEET \(index + 1) placed=\(sheet.placements.count) area=\(sheet.area)")
            for p in sheet.placements {
                emit("PLACE \(p.rect.letter) x=\(p.x) y=\(p.y) w=\(p.width) h=\(p.height)" +
                    (p.rotated ? " rotated" : ""))
            }
            emit(sheet.free.isEmpty
                ? "FREE none" : "FREE " + sheet.free.map(\.description).joined(separator: " "))
            draw(width, height, sheet.placements)
        }
    }

    func process(_ words: [String]) {
        do {
            let command = words[0]
            switch command {
            case "ITEMS":
                try itemsCommand(words)
            case "RANDOM":
                try random(words)
            case "CUTSTOCK":
                try cutstock(words)
            case "SHELF":
                try shelf(words)
            case "GUILLOTINE":
                try guillotine(words)
            default:
                if items == nil { try fail("NO ITEMS") }
                switch command {
                case "NEXTFIT", "FIRSTFIT", "BESTFIT", "WORSTFIT", "ALMOSTWORST",
                     "HARMONIC", "KBOUNDED", "FFD", "BFD", "WFD":
                    method(command, try parameter(command, words, 1))
                case "TRACE":
                    trace(words[1], try parameter(words[1], words, 2))
                case "REDUCE":
                    reduce(words[1], try parameter(words[1], words, 2))
                case "BOUNDS":
                    boundsCommand()
                case "COMPARE":
                    try compare(Int(words[1])!)
                case "EXACT":
                    try exact(Int(words[1])!)
                case "CHECK":
                    try check(words)
                case "COVER":
                    cover()
                case "MULTIFIT":
                    try multifit(Int(words[1])!)
                default:
                    break
                }
            }
        } catch CommandError.reason(let reason) {
            emit("ERROR \(reason)")
        } catch {
            fatalError("Unexpected error: \(error)")
        }
    }
}

let data = FileHandle.standardInput.readDataToEndOfFile()
if let input = String(data: data, encoding: .utf8) {
    let lines = input.split(separator: "\n", omittingEmptySubsequences: true)
    if let first = lines.first, let count = Int(first) {
        let lab = Lab()
        for line in lines.dropFirst().prefix(count) {
            lab.process(line.split(separator: " ").map(String.init))
        }
        if !lab.output.isEmpty {
            print(lab.output.joined(separator: "\n"))
        }
    }
}

struct CommandError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

struct Trace {
    let enabled: Bool
    var lines: [String] = []
    mutating func emit(_ line: String) { if enabled { lines.append(line) } }
}

struct Entry: Equatable {
    let key: Int
    var value: String
    var display: String { "\(key)=\(value)" }
}

struct Node: Equatable {
    var entries: [Entry] = []
    var children: [Int] = []
    var leaf: Bool { children.isEmpty }
    var notation: String { "[" + entries.map { String($0.key) }.joined(separator: " ") + "]" }
    func position(_ key: Int) -> Int { entries.firstIndex { key <= $0.key } ?? entries.count }
}

struct SearchResult {
    let page: Int?
    let index: Int
    let path: [String]
}

enum UpsertResult { case inserted, updated(String) }

struct Tree {
    let degree: Int
    var root = 0
    var pages: [Int: Node] = [0: Node()]
    var splits = 0
    var merges = 0
    var borrows = 0

    func entries() -> [Entry] {
        var result: [Entry] = []
        func visit(_ page: Int) {
            let node = pages[page]!
            if !node.leaf { visit(node.children[0]) }
            for index in node.entries.indices {
                result.append(node.entries[index])
                if !node.leaf { visit(node.children[index + 1]) }
            }
        }
        visit(root)
        return result
    }
    var height: Int {
        var height = 0, page = root
        while !pages[page]!.leaf { height += 1; page = pages[page]!.children[0] }
        return height
    }
    func changes(from before: [Int: Node]) -> (writes: Int, frees: Int) {
        let writes = pages.filter { before[$0.key] != $0.value }.count
        let frees = before.keys.filter { pages[$0] == nil }.count
        return (writes, frees)
    }
    mutating func allocate(_ node: Node) -> Int {
        var page = 0
        while pages[page] != nil { page += 1 }
        pages[page] = node
        return page
    }
    func search(_ key: Int) -> SearchResult {
        var page = root, path: [String] = []
        while true {
            let node = pages[page]!, index = node.position(key)
            path.append(node.notation)
            if index < node.entries.count && node.entries[index].key == key {
                return SearchResult(page: page, index: index, path: path)
            }
            if node.leaf { return SearchResult(page: nil, index: -1, path: path) }
            page = node.children[index]
        }
    }
    func violation() -> String? {
        var referenceDepth: Int?
        func visit(_ page: Int, _ location: String, _ depth: Int, _ low: Int?, _ high: Int?) -> String? {
            let node = pages[page]!, count = node.entries.count
            let minimum = page == root ? (node.leaf ? 0 : 1) : degree - 1, maximum = 2 * degree - 1
            let at = "at=\(location) node=\(node.notation)"
            if count < minimum || count > maximum { return "COUNT \(at) keys=\(count) allowed=\(minimum)..\(maximum)" }
            for index in 0..<max(0, count - 1) {
                if node.entries[index].key >= node.entries[index + 1].key {
                    return "ORDER \(at) \(node.entries[index].key)>=\(node.entries[index + 1].key)"
                }
            }
            for entry in node.entries {
                if (low.map { entry.key <= $0 } ?? false) || (high.map { entry.key >= $0 } ?? false) {
                    return "RANGE \(at) key=\(entry.key) low=\(low.map { String($0) } ?? "-inf") high=\(high.map { String($0) } ?? "+inf")"
                }
            }
            if node.leaf {
                if let expected = referenceDepth {
                    if depth != expected { return "DEPTH \(at) depth=\(depth) expected=\(expected)" }
                } else { referenceDepth = depth }
            }
            for index in node.children.indices {
                if let problem = visit(node.children[index], "\(location).\(index)", depth + 1,
                    index == 0 ? low : node.entries[index - 1].key, index == count ? high : node.entries[index].key) {
                    return problem
                }
            }
            return nil
        }
        return visit(root, "root", 0, nil, nil)
    }
    static func load(degree: Int, tokens: [String]) throws -> Tree {
        var position = 0, nextPage = 0, pages: [Int: Node] = [:]
        func syntax() -> CommandError { CommandError("SYNTAX \(position + 1)") }
        func entry() throws -> Entry {
            guard position < tokens.count, tokens[position] != "(", tokens[position] != ")" else { throw syntax() }
            let words = tokens[position].split(separator: "=")
            position += 1
            return Entry(key: Int(words[0])!, value: String(words[1]))
        }
        func parse() throws -> Int {
            guard position < tokens.count, tokens[position] == "(" else { throw syntax() }
            position += 1
            let page = nextPage
            nextPage += 1
            var node = Node()
            if position < tokens.count && tokens[position] == "(" {
                node.children.append(try parse())
                while position == tokens.count || tokens[position] != ")" {
                    node.entries.append(try entry()); node.children.append(try parse())
                }
            } else {
                while position == tokens.count || tokens[position] != ")" { node.entries.append(try entry()) }
            }
            position += 1
            pages[page] = node
            return page
        }
        let root = try parse()
        guard position == tokens.count else { throw syntax() }
        var tree = Tree(degree: degree)
        tree.root = root; tree.pages = pages
        return tree
    }
    mutating func split(_ parentPage: Int, _ index: Int, trace: inout Trace) {
        var parent = pages[parentPage]!
        let childPage = parent.children[index]
        var child = pages[childPage]!
        let before = child.notation, middle = child.entries[degree - 1]
        let right = Node(entries: Array(child.entries.dropFirst(degree)), children: Array(child.children.dropFirst(degree)))
        let newPage = allocate(right)
        child.entries = Array(child.entries.prefix(degree - 1)); child.children = Array(child.children.prefix(degree))
        parent.entries.insert(middle, at: index); parent.children.insert(newPage, at: index + 1)
        pages[childPage] = child; pages[parentPage] = parent; splits += 1
        trace.emit("STEP split page=\(childPage) keys=\(before) up=\(middle.key) new=\(newPage)")
    }
    mutating func upsert(_ key: Int, _ value: String, trace: inout Trace) -> UpsertResult {
        let found = search(key)
        if let page = found.page {
            let old = pages[page]!.entries[found.index].value
            pages[page]!.entries[found.index].value = value
            return .updated(old)
        }
        if pages[root]!.entries.count == 2 * degree - 1 {
            let newRoot = allocate(Node(children: [root]))
            root = newRoot
            trace.emit("STEP grow page=\(root)")
            split(root, 0, trace: &trace)
        }
        var page = root
        while !pages[page]!.leaf {
            var index = pages[page]!.position(key)
            if pages[pages[page]!.children[index]]!.entries.count == 2 * degree - 1 {
                split(page, index, trace: &trace)
                if key > pages[page]!.entries[index].key { index += 1 }
            }
            page = pages[page]!.children[index]
        }
        var node = pages[page]!
        let position = node.position(key)
        node.entries.insert(Entry(key: key, value: value), at: position)
        pages[page] = node
        trace.emit("STEP place page=\(page) keys=\(node.notation)")
        return .inserted
    }
    mutating func merge(_ parentPage: Int, _ index: Int, _ caseName: String, trace: inout Trace) -> Int {
        var parent = pages[parentPage]!
        let leftPage = parent.children[index], rightPage = parent.children[index + 1], right = pages[rightPage]!
        var left = pages[leftPage]!
        left.entries.append(parent.entries.remove(at: index))
        left.entries.append(contentsOf: right.entries); left.children.append(contentsOf: right.children)
        parent.children.remove(at: index + 1)
        pages[leftPage] = left; pages[parentPage] = parent; pages[rightPage] = nil; merges += 1
        trace.emit("STEP \(caseName) page=\(parentPage) merge=\(leftPage)+\(rightPage) keys=\(left.notation)")
        if parentPage == root && parent.entries.isEmpty {
            root = leftPage; pages[parentPage] = nil
            trace.emit("STEP shrink page=\(root)")
        }
        return leftPage
    }
    mutating func removeAt(_ page: Int, _ key: Int, cases: inout [String], trace: inout Trace) {
        var node = pages[page]!
        let index = node.position(key)
        if index < node.entries.count && node.entries[index].key == key {
            if node.leaf {
                cases.append("1"); node.entries.remove(at: index); pages[page] = node
                trace.emit("STEP 1 page=\(page) keys=\(node.notation)")
                return
            }
            let left = node.children[index], right = node.children[index + 1]
            if pages[left]!.entries.count >= degree {
                var last = left
                while !pages[last]!.leaf { last = pages[last]!.children.last! }
                let predecessor = pages[last]!.entries.last!
                cases.append("2a"); trace.emit("STEP 2a page=\(page) pred=\(predecessor.key)")
                removeAt(left, predecessor.key, cases: &cases, trace: &trace)
                pages[page]!.entries[index] = predecessor
            } else if pages[right]!.entries.count >= degree {
                var first = right
                while !pages[first]!.leaf { first = pages[first]!.children[0] }
                let successor = pages[first]!.entries[0]
                cases.append("2b"); trace.emit("STEP 2b page=\(page) succ=\(successor.key)")
                removeAt(right, successor.key, cases: &cases, trace: &trace)
                pages[page]!.entries[index] = successor
            } else {
                cases.append("2c")
                let child = merge(page, index, "2c", trace: &trace)
                removeAt(child, key, cases: &cases, trace: &trace)
            }
            return
        }
        var childPage = node.children[index], child = pages[node.children[index]]!
        if child.entries.count == degree - 1 {
            let leftPage: Int? = index > 0 ? node.children[index - 1] : nil
            let rightPage: Int? = index < node.entries.count ? node.children[index + 1] : nil
            if let leftPage, pages[leftPage]!.entries.count >= degree {
                var left = pages[leftPage]!
                cases.append("3a-left")
                child.entries.insert(node.entries[index - 1], at: 0)
                node.entries[index - 1] = left.entries.removeLast()
                if !left.leaf { child.children.insert(left.children.removeLast(), at: 0) }
                pages[page] = node; pages[childPage] = child; pages[leftPage] = left; borrows += 1
                trace.emit("STEP 3a-left page=\(page) child=\(childPage) from=\(leftPage) keys=\(child.notation)")
            } else if let rightPage, pages[rightPage]!.entries.count >= degree {
                var right = pages[rightPage]!
                cases.append("3a-right")
                child.entries.append(node.entries[index]); node.entries[index] = right.entries.removeFirst()
                if !right.leaf { child.children.append(right.children.removeFirst()) }
                pages[page] = node; pages[childPage] = child; pages[rightPage] = right; borrows += 1
                trace.emit("STEP 3a-right page=\(page) child=\(childPage) from=\(rightPage) keys=\(child.notation)")
            } else if leftPage != nil {
                cases.append("3b-left"); childPage = merge(page, index - 1, "3b-left", trace: &trace)
            } else {
                cases.append("3b-right"); childPage = merge(page, index, "3b-right", trace: &trace)
            }
        }
        removeAt(childPage, key, cases: &cases, trace: &trace)
    }
    mutating func remove(_ key: Int, trace: inout Trace) -> [String] {
        var cases: [String] = []
        removeAt(root, key, cases: &cases, trace: &trace)
        return cases
    }
    func scan(_ low: Int, _ high: Int) -> (entries: [Entry], visited: Int) {
        var entries: [Entry] = [], visited = 0
        func visit(_ page: Int) {
            visited += 1
            let node = pages[page]!, count = node.entries.count
            for index in 0...count {
                if !node.leaf && (index == 0 || node.entries[index - 1].key < high)
                    && (index == count || node.entries[index].key > low) { visit(node.children[index]) }
                if index < count && low <= node.entries[index].key && node.entries[index].key <= high {
                    entries.append(node.entries[index])
                }
            }
        }
        visit(root)
        return (entries, visited)
    }
    func dump() -> String {
        var tokens: [String] = []
        func visit(_ page: Int) {
            let node = pages[page]!
            tokens.append("(")
            if !node.leaf { visit(node.children[0]) }
            for index in node.entries.indices {
                tokens.append(node.entries[index].display)
                if !node.leaf { visit(node.children[index + 1]) }
            }
            tokens.append(")")
        }
        visit(root)
        return tokens.joined(separator: " ")
    }
    mutating func compact() {
        var source = entries(), children: [Int] = [], built: [Node] = []
        var oldRoot = 0
        while true {
            let groups = (source.count + 2 * degree) / (2 * degree), keys = source.count - groups + 1
            let size = keys / groups, extra = keys % groups
            var nodes: [Int] = [], separators: [Entry] = [], entryIndex = 0, childIndex = 0
            for group in 0..<groups {
                let count = size + (group < extra ? 1 : 0)
                let node = Node(entries: Array(source[entryIndex..<(entryIndex + count)]),
                    children: children.isEmpty ? [] : Array(children[childIndex..<(childIndex + count + 1)]))
                nodes.append(built.count); built.append(node)
                entryIndex += count; childIndex += count + 1
                if group + 1 < groups { separators.append(source[entryIndex]); entryIndex += 1 }
            }
            if groups == 1 { oldRoot = nodes[0]; break }
            source = separators; children = nodes
        }
        var replacement: [Int: Node] = [:], nextPage = 0
        func renumber(_ oldPage: Int) -> Int {
            let page = nextPage
            nextPage += 1
            var node = built[oldPage]
            node.children = node.children.map { renumber($0) }
            replacement[page] = node
            return page
        }
        root = renumber(oldRoot); pages = replacement
        splits = 0; merges = 0; borrows = 0
    }
}

enum Verb: String {
    case create = "CREATE", load = "LOAD", insert = "INSERT", bulkLoad = "BULKLOAD", delete = "DELETE"
    case delRange = "DELRANGE", get = "GET", range = "RANGE", count = "COUNT", min = "MIN", max = "MAX"
    case floor = "FLOOR", ceil = "CEIL", rank = "RANK", select = "SELECT", seek = "SEEK", next = "NEXT", prev = "PREV"
    case print = "PRINT", pages = "PAGES", dump = "DUMP", height = "HEIGHT", stats = "STATS", verify = "VERIFY"
    case rebuild = "REBUILD", compact = "COMPACT", save = "SAVE", restore = "RESTORE", trace = "TRACE"
    var requiresValidTree: Bool {
        switch self {
        case .insert, .bulkLoad, .delete, .delRange, .range, .count, .min, .max, .floor, .ceil, .rank,
             .select, .seek, .next, .prev, .height, .compact: return true
        default: return false
        }
    }
}

enum Cursor: Equatable { case unset, key(Int), begin, end }

final class Workbench {
    private var index: Tree?
    private var saved: Tree?
    private var cursor = Cursor.unset
    private var trace = false

    private func summary(_ prefix: String, _ tree: Tree) -> String {
        "\(prefix) nodes=\(tree.pages.count) keys=\(tree.entries().count) \(tree.violation() == nil ? "OK" : "DAMAGED")"
    }
    func command(_ line: String) throws -> [String] {
        let words = line.split(separator: " ").map(String.init), verb = Verb(rawValue: words[0])!
        let args = Array(words.dropFirst())
        if verb == .trace { trace = args[0] == "ON"; return ["TRACE \(args[0])"] }
        let first = args.isEmpty ? 0 : Int(args[0])!
        let ranged = [Verb.delRange, .range, .count].contains(verb), second = ranged ? Int(args[1])! : 0
        if verb == .create || verb == .load {
            guard (2...5).contains(first) else { throw CommandError("BAD DEGREE \(first)") }
            let replacement: Tree
            if verb == .create { replacement = Tree(degree: first) }
            else { replacement = try Tree.load(degree: first, tokens: Array(args.dropFirst())) }
            index = replacement; cursor = .unset
            return [verb == .create ? "CREATE t=\(first)" : summary("LOAD t=\(first)", replacement)]
        }
        guard var tree = index else { throw CommandError("NO INDEX") }
        if verb.requiresValidTree && tree.violation() != nil { throw CommandError("DAMAGED") }
        let entries = tree.entries()
        if ranged && first > second { throw CommandError("BAD RANGE \(first) \(second)") }
        if verb == .select && (first < 1 || first > entries.count) { throw CommandError("BAD POSITION \(first)") }
        if (verb == .next || verb == .prev) && cursor == .unset { throw CommandError("NO CURSOR") }
        if verb == .restore && saved == nil { throw CommandError("NO SAVE") }
        var output: [String] = [], steps = Trace(enabled: trace && (verb == .insert || verb == .delete))
        switch verb {
        case .insert:
            let before = tree.pages, splits = tree.splits
            let result = tree.upsert(first, args[1], trace: &steps), writes = tree.changes(from: before).writes
            output += steps.lines
            switch result {
            case .inserted: output.append("INSERT \(first) NEW splits=\(tree.splits - splits) height=\(tree.height) writes=\(writes)")
            case .updated(let old): output.append("INSERT \(first) UPDATED old=\(old) writes=\(writes)")
            }
        case .bulkLoad:
            let before = tree.pages, splits = tree.splits
            var inserted = 0, updated = 0
            for position in stride(from: 0, to: args.count, by: 2) {
                if case .inserted = tree.upsert(Int(args[position])!, args[position + 1], trace: &steps) { inserted += 1 }
                else { updated += 1 }
            }
            output.append("BULKLOAD pairs=\(args.count / 2) new=\(inserted) updated=\(updated) splits=\(tree.splits - splits) height=\(tree.height) writes=\(tree.changes(from: before).writes)")
        case .delete:
            let found = tree.search(first)
            if let page = found.page {
                let value = tree.pages[page]!.entries[found.index].value, before = tree.pages
                let cases = tree.remove(first, trace: &steps), changes = tree.changes(from: before)
                output += steps.lines
                output.append("DELETE \(first) REMOVED value=\(value) cases=\(cases.joined(separator: ",")) height=\(tree.height) writes=\(changes.writes) frees=\(changes.frees)")
            } else { output.append("DELETE \(first) NOT FOUND") }
        case .delRange:
            let before = tree.pages, merges = tree.merges, borrows = tree.borrows
            var removed = 0
            for entry in entries where first <= entry.key && entry.key <= second {
                _ = tree.remove(entry.key, trace: &steps); removed += 1
            }
            let changes = tree.changes(from: before)
            output.append("DELRANGE \(first) \(second) removed=\(removed) merges=\(tree.merges - merges) borrows=\(tree.borrows - borrows) height=\(tree.height) writes=\(changes.writes) frees=\(changes.frees)")
        case .get:
            let found = tree.search(first)
            let result = found.page.map { "FOUND value=\(tree.pages[$0]!.entries[found.index].value)" } ?? "NOT FOUND"
            output.append("GET \(first) \(result) path=\(found.path.joined(separator: " -> "))")
        case .range, .count:
            let result = tree.scan(first, second)
            let suffix = verb == .range ? result.entries.map { " " + $0.display }.joined() : ""
            output.append("\(verb.rawValue) \(first) \(second) count=\(result.entries.count) visited=\(result.visited)\(suffix)")
        case .min, .max:
            let entry = verb == .min ? entries.first : entries.last
            output.append("\(verb.rawValue) \(entry?.display ?? "EMPTY")")
        case .floor, .ceil:
            let entry = verb == .floor ? entries.last(where: { $0.key <= first }) : entries.first(where: { $0.key >= first })
            output.append("\(verb.rawValue) \(first) \(entry?.display ?? "NONE")")
        case .rank:
            output.append("RANK \(first) \(entries.filter { $0.key < first }.count)")
        case .select:
            output.append("SELECT \(first) \(entries[first - 1].display)")
        case .seek:
            let entry = entries.first { $0.key >= first }
            cursor = entry.map { .key($0.key) } ?? .end
            output.append("SEEK \(first) \(entry?.display ?? "END")")
        case .next, .prev:
            var entry: Entry?
            if verb == .next {
                switch cursor {
                case .begin: entry = entries.first
                case .key(let key): entry = entries.first { $0.key > key }
                case .end, .unset: break
                }
                cursor = entry.map { .key($0.key) } ?? .end
            } else {
                switch cursor {
                case .end: entry = entries.last
                case .key(let key): entry = entries.last { $0.key < key }
                case .begin, .unset: break
                }
                cursor = entry.map { .key($0.key) } ?? .begin
            }
            output.append("\(verb.rawValue) \(entry?.display ?? (verb == .next ? "END" : "BEGIN"))")
        case .print:
            var level = [tree.root], depth = 0
            while !level.isEmpty {
                output.append("LEVEL \(depth) " + level.map { tree.pages[$0]!.notation }.joined(separator: " "))
                level = level.flatMap { tree.pages[$0]!.children }; depth += 1
            }
        case .pages:
            for page in tree.pages.keys.sorted() {
                let node = tree.pages[page]!
                let children = node.leaf ? "-" : node.children.map { String($0) }.joined(separator: ",")
                output.append("PAGE \(page) \(node.notation) kids=\(children)")
            }
        case .dump: output.append("DUMP \(tree.degree) \(tree.dump())")
        case .height: output.append("HEIGHT \(tree.height)")
        case .stats:
            let leaves = tree.pages.values.filter { $0.leaf }.count
            let fill = 100 * entries.count / ((2 * tree.degree - 1) * tree.pages.count)
            output.append("STATS t=\(tree.degree) nodes=\(tree.pages.count) leaves=\(leaves) keys=\(entries.count) fill=\(fill)% splits=\(tree.splits) merges=\(tree.merges) borrows=\(tree.borrows)")
        case .verify:
            output.append(tree.violation().map { "VERIFY FAIL " + $0 } ?? "VERIFY OK")
        case .rebuild:
            tree = Tree(degree: tree.degree)
            for entry in entries { _ = tree.upsert(entry.key, entry.value, trace: &steps) }
            output.append("REBUILD entries=\(entries.count) keys=\(tree.entries().count) nodes=\(tree.pages.count) splits=\(tree.splits) height=\(tree.height)")
        case .compact:
            let nodes = tree.pages.count
            tree.compact()
            output.append("COMPACT nodes=\(nodes)->\(tree.pages.count) height=\(tree.height)")
        case .save: saved = tree; output.append(summary("SAVE", tree))
        case .restore: tree = saved!; output.append(summary("RESTORE", tree))
        case .create, .load, .trace: break
        }
        index = tree
        return output
    }
}

let count = Int(readLine()!)!, workbench = Workbench()
for _ in 0..<count {
    let line = readLine()!
    do { for result in try workbench.command(line) { print(result) } }
    catch let error as CommandError { print("ERROR \(error.message)") }
    catch { fatalError("Unexpected error: \(error)") }
}

import Foundation

indirect enum Value {
    case absent, string(String), integer(Int), boolean(Bool), list([Value]), map([String: Value])
}

struct Problem: Error {
    var line = 0
    var reason: String
}

func cut(_ s: String, _ a: Int, _ b: Int? = nil) -> String {
    String(decoding: Array(s.utf8)[a..<(b ?? s.utf8.count)], as: UTF8.self)
}
func find(_ s: String, _ needle: String, _ at: Int = 0) -> Int? {
    let tail = cut(s, at)
    guard let range = tail.range(of: needle) else {
        return nil
    }
    return at + tail.distance(from: tail.startIndex, to: range.lowerBound)
}
func trim(_ s: String) -> String {
    s.trimmingCharacters(in: CharacterSet(charactersIn: " "))
}
func letter(_ c: UInt8) -> Bool {
    (65...90).contains(c) || (97...122).contains(c)
}
func digit(_ c: UInt8) -> Bool {
    (48...57).contains(c)
}
func identifier(_ s: String) -> Bool {
    let b = Array(s.utf8)
    return !b.isEmpty && (letter(b[0]) || b[0] == 95) && b.allSatisfy { letter($0) || digit($0) || $0 == 95 }
}
func subscriptName(_ s: String) -> Bool {
    let b = Array(s.utf8)
    return s == "0" || (!b.isEmpty && b[0] != 48 && b.allSatisfy(digit))
}
func integerArgument(_ s: String) -> Int? {
    let b = Array((s.hasPrefix("-") ? cut(s, 1) : s).utf8)
    return (1...9).contains(b.count) && b.allSatisfy(digit) ? Int(s) : nil
}

enum Part { case key(String), index(Int) }
struct KeyPart { let part: Part
    let prefix: String
}
func keyParts(_ s: String) -> [KeyPart]? {
    let b = Array(s.utf8)
    var at = 0, result: [KeyPart] = []
    while true {
        let start = at
        while at < b.count && (letter(b[at]) || digit(b[at]) || b[at] == 95) {
            at += 1
        }
        guard identifier(cut(s, start, at)) else {
            return nil
        }
        result.append(KeyPart(part: .key(cut(s, start, at)), prefix: cut(s, 0, at)))
        while true {
            if at == b.count {
                return result
            }
            if b[at] == 46 {
                at += 1
                break
            }
            guard b[at] == 91, let end = find(s, "]", at + 1), subscriptName(cut(s, at + 1, end)), let index = Int(cut(
                s,
                at + 1,
                end
            )) else {
                return nil
            }
            at = end + 1
            result.append(KeyPart(part: .index(index), prefix: cut(s, 0, at)))
        }
    }
}
func scalar(_ s: String, _ at: inout Int) -> Value? {
    let b = Array(s.utf8)
    if at < b.count && b[at] == 34 {
        at += 1
        var text: [UInt8] = []
        while at < b.count {
            let c = b[at]
            at += 1
            if c == 34 {
                return .string(String(decoding: text, as: UTF8.self))
            }
            if c == 92 {
                guard at < b.count else {
                    return nil
                }
                switch b[at] {
                case 34:
                    text.append(34)
                case 92:
                    text.append(92)
                case 110:
                    text.append(10)
                default:
                    return nil
                }
                at += 1
            } else {
                text.append(c)
            }
        }
        return nil
    }
    let start = at
    while at < b.count && b[at] != 44 && b[at] != 93 {
        at += 1
    }
    let word = cut(s, start, at)
    if word == "true" {
        return .boolean(true)
    }
    if word == "false" {
        return .boolean(false)
    }
    let digits = word.hasPrefix("-") ? cut(word, 1) : word
    guard word != "-0", subscriptName(digits), let n = Int(word) else {
        return nil
    }
    return .integer(n)
}
func parseValue(_ s: String) -> Value? {
    if s == "{}" {
        return .map([:])
    }
    if s == "[]" {
        return .list([])
    }
    var at = 0
    if s.hasPrefix("[") {
        at = 1
        var list: [Value] = []
        while true {
            guard let value = scalar(s, &at) else {
                return nil
            }
            list.append(value)
            if cut(s, at).hasPrefix("]") {
                return at + 1 == s.utf8.count ? .list(list) : nil
            }
            guard cut(s, at).hasPrefix(", ") else {
                return nil
            }
            at += 2
        }
    }
    guard let value = scalar(s, &at), at == s.utf8.count else {
        return nil
    }
    return value
}
func child(_ value: Value, _ part: Part) -> Value? {
    switch (value, part) {
    case (.map(let map), .key(let key)):
        return map[key]
    case (.list(let list), .index(let index)):
        return index < list.count ? list[index] : nil
    default:
        return nil
    }
}
func assigning(_ container: Value, _ parts: ArraySlice<KeyPart>, _ value: Value) throws -> Value {
    let first = parts.first!
    if case .list(let list) = container, case .index(let i) = first.part, i > list.count {
        throw Problem(reason: "index gap at '\(first.prefix)'")
    }
    var next = value
    if parts.count > 1 {
        let mapNeeded: Bool
        if case .key = parts.dropFirst().first!.part {
            mapNeeded = true
        } else {
            mapNeeded = false
        }
        let old = child(container, first.part) ?? (mapNeeded ? .map([:]) : .list([]))
        switch (old, mapNeeded) {
        case (.map, true), (.list, false):
            break
        default:
            throw Problem(reason: "type conflict at '\(first.prefix)'")
        }
        next = try assigning(old, parts.dropFirst(), value)
    }
    switch (container, first.part) {
    case (.map(var map), .key(let key)):
        map[key] = next
        return .map(map)
    case (.list(var list), .index(let i)):
        if i == list.count {
            list.append(next)
        } else {
            list[i] = next
        }
        return .list(list)
    default:
        fatalError("invalid container")
    }
}
func removing(_ container: Value, _ parts: ArraySlice<KeyPart>) -> Value? {
    let part = parts.first!.part
    guard let old = child(container, part) else {
        return nil
    }
    if parts.count == 1 {
        switch (container, part) {
        case (.map(var map), .key(let key)):
            map.removeValue(forKey: key)
            return .map(map)
        case (.list(var list), .index(let i)):
            list.remove(at: i)
            return .list(list)
        default:
            return nil
        }
    }
    guard let next = removing(old, parts.dropFirst()) else {
        return nil
    }
    switch (container, part) {
    case (.map(var map), .key(let key)):
        map[key] = next
        return .map(map)
    case (.list(var list), .index(let i)):
        list[i] = next
        return .list(list)
    default:
        return nil
    }
}
func stringify(_ v: Value) throws -> String {
    switch v {
    case .absent:
        return ""
    case .string(let s):
        return s
    case .integer(let n):
        return String(n)
    case .boolean(let b):
        return b ? "true" : "false"
    case .list(let list):
        return try list.map(stringify).joined(separator: ", ")
    case .map:
        throw Problem(reason: "cannot render map")
    }
}
func truthy(_ v: Value) -> Bool {
    switch v {
    case .absent:
        return false
    case .string(let s):
        return !s.isEmpty
    case .integer(let n):
        return n != 0
    case .boolean(let b):
        return b
    case .list(let list):
        return !list.isEmpty
    case .map(let map):
        return !map.isEmpty
    }
}
func number(_ v: Value, _ filter: String) throws -> Int {
    switch v {
    case .absent:
        return 0
    case .integer(let n):
        return n
    case .string(let s):
        if let n = integerArgument(s) {
            return n
        }
    default:
        break
    }
    throw Problem(reason: "not a number for '\(filter)'")
}
func quotedSplit(_ s: String, _ separator: UInt8) -> [String] {
    var quoted = false, start = 0, result: [String] = []
    for (i, c) in s.utf8.enumerated() {
        if c == 39 {
            quoted.toggle()
        }
        if c == separator && !quoted {
            result.append(cut(s, start, i))
            start = i + 1
        }
    }
    result.append(cut(s, start))
    return result
}
func validName(_ s: String) -> Bool {
    s == "." || ["@index", "@number", "@first", "@last"].contains(s) || s.components(separatedBy: ".")
        .allSatisfy { identifier($0) || subscriptName($0) }
}
struct Filter { let name: String
    let args: [Value]
}
struct Expression { let name: String
    let filters: [Filter]
}
func expression(_ s: String) throws -> Expression {
    let pieces = quotedSplit(s, 124), name = trim(pieces[0])
    guard validName(name) else {
        throw Problem(reason: "invalid name '\(name)'")
    }
    let noArgs = [
        "upper",
        "lower",
        "title",
        "trim",
        "length",
        "first",
        "last",
        "reverse",
        "items",
        "comma",
        "sum",
        "min",
        "max"
    ]
    let others = [
        "default",
        "eq",
        "pad",
        "lpad",
        "truncate",
        "replace",
        "join",
        "sort",
        "pluck",
        "add",
        "sub",
        "mul",
        "div",
        "mod",
        "gt",
        "lt"
    ]
    var filters: [Filter] = []
    for piece in pieces.dropFirst() {
        let items = quotedSplit(trim(piece), 58), f = items[0]
        guard noArgs.contains(f) || others.contains(f) else {
            throw Problem(reason: "unknown filter '\(f)'")
        }
        var args: [Value] = []
        for arg in items.dropFirst() {
            if arg.utf8.count >= 2 && arg.hasPrefix("'") && arg.hasSuffix("'") && !cut(arg, 1, arg.utf8.count - 1)
                .contains("'")
            {
                args.append(.string(cut(arg, 1, arg.utf8.count - 1)))
            } else if let n = integerArgument(arg) {
                args.append(.integer(n))
            } else {
                throw Problem(reason: "bad arguments for '\(f)'")
            }
        }
        func stringArg(_ i: Int) -> String? {
            if i < args.count, case .string(let s) = args[i] {
                return s
            }
            return nil
        }
        func intArg(_ i: Int) -> Int? {
            if i < args.count, case .integer(let n) = args[i] {
                return n
            }
            return nil
        }
        var good = false
        if noArgs.contains(f) {
            good = args.isEmpty
        } else {
            switch f {
            case "default", "eq":
                good = args.count == 1
            case "pad",
                 "lpad":
                good = (args.count == 1 || args.count == 2) && (intArg(0) ?? -1) >= 0 &&
                    (args.count == 1 || stringArg(1)?.utf8.count == 1)
            case "truncate":
                good = args.count == 1 && (intArg(0) ?? -1) >= 0
            case "replace":
                good = args.count == 2 && !(stringArg(0) ?? "").isEmpty && stringArg(1) != nil
            case "join", "pluck":
                good = args.count == 1 && stringArg(0) != nil
            case "sort":
                good = args.isEmpty || (args.count == 1 && stringArg(0) != nil)
            case "div", "mod":
                good = args.count == 1 && intArg(0) != nil && intArg(0) != 0
            default:
                good = args.count == 1 && intArg(0) != nil
            }
        }
        guard good else {
            throw Problem(reason: "bad arguments for '\(f)'")
        }
        filters.append(Filter(name: f, args: args))
    }
    return Expression(name: name, filters: filters)
}
func sortCompare(_ a: Value, _ b: Value) -> Int {
    func rank(_ v: Value) -> Int {
        switch v { case .absent:
            return 0
        case .integer:
            return 1
        case .string:
            return 2
        case .boolean:
            return 3
        default:
            return 4 }
    }
    if rank(a) != rank(b) {
        return rank(a) < rank(b) ? -1 : 1
    }
    switch (a, b) {
    case (.integer(let a), .integer(let b)):
        return a == b ? 0 : (a < b ? -1 : 1)
    case (.string(let a), .string(let b)):
        return a == b ? 0 : (a < b ? -1 : 1)
    case (.boolean(let a), .boolean(let b)):
        return a == b ? 0 : (!a ? -1 : 1)
    default:
        return 0
    }
}
func applyFilter(_ v: Value, _ f: Filter) throws -> Value {
    let name = f.name
    func n() -> Int {
        if case .integer(let x) = f.args[0] {
            return x
        }
        fatalError("integer argument")
    }
    func s(_ i: Int) -> String {
        if case .string(let x) = f.args[i] {
            return x
        }
        fatalError("string argument")
    }
    switch name {
    case "default":
        return truthy(v) ? v : f.args[0]
    case "eq":
        return .boolean(try stringify(v) == stringify(f.args[0]))
    case "length":
        switch v { case .list(let l):
            return .integer(l.count)
        case .map(let m):
            return .integer(m.count)
        default:
            return .integer(try stringify(v).utf8.count) }
    case "first", "last":
        if case .list(let l) = v {
            return (name == "first" ? l.first : l.last) ?? .absent
        }
        return v
    case "reverse":
        switch v { case .list(let l):
            return .list(Array(l.reversed()))
        case .string(let t):
            return .string(String(t.reversed()))
        default:
            return v }
    case "items":
        if case .map(let m) = v {
            return .list(m.keys.sorted().map { .map(["key": .string($0), "value": m[$0]!]) })
        }
        return v
    case "sort":
        guard case .list(let l) = v else {
            return v
        }
        func key(_ item: Value) -> Value {
            if f.args.isEmpty {
                return item
            }
            if case .map(let m) = item {
                return m[s(0)] ?? .absent
            }
            return .absent
        }
        return .list(l.enumerated().sorted { let order = sortCompare(key($0.element), key($1.element))
            return order == 0 ? $0.offset < $1.offset : order < 0
        }.map { $0.element })
    case "pluck":
        if case .list(let l) = v {
            return .list(l.map {
                if case .map(let m) = $0 {
                    return m[s(0)] ?? .absent
                }
                return .absent
            })
        }
        return v
    case "sum", "min", "max":
        if case .list(let l) = v {
            let nums = try l.map { try number($0, name) }
            if name == "sum" {
                return .integer(nums.reduce(0, +))
            }
            return (name == "min" ? nums.min() : nums.max()).map(Value.integer) ?? .absent
        }
        return .integer(try number(v, name))
    case "add", "sub", "mul", "div", "mod", "gt", "lt":
        let a = try number(v, name), b = n()
        func floorQuotient() -> Int {
            let q = a / b
            return a % b != 0 && (a < 0) != (b < 0) ? q - 1 : q
        }
        switch name { case "add":
            return .integer(a + b)
        case "sub":
            return .integer(a - b)
        case "mul":
            return .integer(a * b)
        case "div":
            return .integer(floorQuotient())
        case "mod":
            return .integer(a - b * floorQuotient())
        case "gt":
            return .boolean(a > b)
        default:
            return .boolean(a < b) }
    case "comma":
        let a = try number(v, name), digits = Array(String(abs(a)))
        var text = a < 0 ? "-" : ""
        for (i, c) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 {
                text += ","
            }
            text.append(c)
        }
        return .string(text)
    case "join":
        if case .list(let l) = v {
            return .string(try l.map(stringify).joined(separator: s(0)))
        }
        return .string(try stringify(v))
    default:
        let text = try stringify(v)
        switch name {
        case "upper":
            return .string(text.uppercased())
        case "lower":
            return .string(text.lowercased())
        case "trim":
            return .string(trim(text))
        case "title":
            var first = true, result = ""
            for c in text {
                result += first ? String(c).uppercased() : String(c).lowercased()
                first = c == " "
            }
            return .string(result)
        case "pad", "lpad":
            let padding = String(repeating: f.args.count == 2 ? s(1) : " ", count: max(0, n() - text.utf8.count))
            return .string(name == "pad" ? text + padding : padding + text)
        case "truncate":
            return .string(text.utf8.count > n() ? cut(text, 0, n()) + "..." : text)
        default:
            return .string(text.replacingOccurrences(of: s(0), with: s(1)))
        }
    }
}

struct SourceLine { let line: Int
    let text: String
}
struct Tag {
    var kind: Character
    var text: String
    var expr: Expression? = nil
    var line: Int
    var indent = ""
    var end = 0
}
func analyze(_ source: [SourceLine]) throws -> [Tag] {
    var open = "{{", close = "}}", stack: [(String, Int)] = [], tokens: [Tag] = []
    for row in source {
        let text = row.text, line = row.line
        var at = 0, tags: [Tag] = []
        while let start = find(text, open, at) {
            tags.append(Tag(kind: "t", text: cut(text, at, start), line: line))
            var begin = start + open.utf8.count
            let triple = cut(text, begin).hasPrefix("{")
            if triple {
                begin += 1
            }
            let ending = triple ? "}" + close : close
            guard let finish = find(text, ending, begin) else {
                throw Problem(line: line, reason: "unclosed tag")
            }
            let content = trim(cut(text, begin, finish))
            at = finish + ending.utf8.count
            let kind: Character, arg: String
            if triple {
                kind = "&"
                arg = content
            } else if let first = content.first, "#^/!>&=".contains(first) {
                kind = first
                arg = trim(cut(content, 1))
            } else {
                kind = "v"
                arg = content
            }
            var tag = Tag(kind: kind, text: arg, line: line)
            do {
                switch kind {
                case "v", "&", "#", "^":
                    let expr = try expression(arg)
                    tag.expr = expr
                    if kind == "#" || kind == "^" {
                        stack.append((expr.name, line))
                    }
                case "/":
                    guard validName(arg) else {
                        throw Problem(reason: "invalid name '\(arg)'")
                    }
                    guard let top = stack.last else {
                        throw Problem(reason: "unexpected closing '\(arg)'")
                    }
                    guard top.0 == arg
                    else {
                        throw Problem(reason: "mismatched closing '\(arg)', expected '\(top.0)'")
                    }
                    stack.removeLast()
                case ">":
                    if !identifier(arg) {
                        throw Problem(reason: "invalid name '\(arg)'")
                    }
                case "=":
                    guard content.utf8.count >= 2 && content.hasSuffix("=")
                    else {
                        throw Problem(reason: "invalid delimiters")
                    }
                    let pair = cut(content, 1, content.utf8.count - 1).split(separator: " ").map(String.init)
                    guard pair.count == 2 && pair.allSatisfy({ !$0.contains("=") })
                    else {
                        throw Problem(reason: "invalid delimiters")
                    }
                    open = pair[0]
                    close = pair[1]
                default:
                    break
                }
            } catch let error as Problem { throw Problem(line: line, reason: error.reason) }
            tags.append(tag)
        }
        tags.append(Tag(kind: "t", text: cut(text, at), line: line))
        let positions = tags.indices.filter { tags[$0].kind != "t" }
        if positions.count == 1 && "#^/!>=".contains(tags[positions[0]].kind) && tags.filter({ $0.kind == "t" })
            .allSatisfy({ $0.text.allSatisfy { $0 == " " } })
        {
            let i = positions[0]
            var tag = tags[i]
            if tag.kind == ">" {
                tag.indent = tags[..<i].map(\.text).joined()
            }
            tokens.append(tag)
        } else {
            tokens += tags
            tokens.append(Tag(kind: "t", text: "\n", line: line))
        }
    }
    if let top = stack.last {
        throw Problem(line: top.1, reason: "unclosed section '\(top.0)'")
    }
    var openings: [Int] = []
    for i in tokens.indices {
        if tokens[i].kind == "#" || tokens[i].kind == "^" {
            openings.append(i)
        }
        if tokens[i].kind == "/" {
            let start = openings.removeLast()
            tokens[start].end = i
        }
    }
    return tokens
}
func resolve(_ name: String, _ contexts: [Value], _ loops: [(Int, Int)]) -> Value? {
    if name == "." {
        return contexts.last
    }
    if name.hasPrefix("@") {
        guard let (i, n) = loops.last else {
            return nil
        }
        switch name { case "@index":
            return .integer(i)
        case "@number":
            return .integer(i + 1)
        case "@first":
            return .boolean(i == 0)
        default:
            return .boolean(i == n - 1) }
    }
    let parts: [Part] = name.components(separatedBy: ".")
        .map { subscriptName($0) ? .index(Int($0) ?? Int.max) : .key($0) }
    for context in contexts.reversed() {
        if var value = child(context, parts[0]) {
            for part in parts.dropFirst() {
                guard let next = child(value, part)
                else {
                    return nil
                }
                value = next
            }
            return value
        }
    }
    return nil
}
func escape(_ s: String) -> String {
    s.map { c in switch c { case "&":
        return "&amp;"
    case "<":
        return "&lt;"
    case ">":
        return "&gt;"
    case "\"":
        return "&quot;"
    case "'":
        return "&#39;"
    default:
        return String(c) } }.joined()
}
func render(
    _ tags: [Tag],
    _ start: Int,
    _ end: Int,
    _ contexts: [Value],
    _ loops: [(Int, Int)],
    _ partials: [String: [SourceLine]],
    _ strict: Bool,
    _ depth: Int
) throws -> String {
    var result = "", at = start
    while at < end {
        let tag = tags[at]
        do {
            switch tag.kind {
            case "t":
                result += tag.text
            case "v", "&", "#", "^":
                let expr = tag.expr!, found = resolve(expr.name, contexts, loops)
                if strict && (tag.kind == "v" || tag.kind == "&") && found ==
                    nil
                {
                    throw Problem(reason: "missing '\(expr.name)'")
                }
                var value = found ?? .absent
                for filter in expr.filters {
                    value = try applyFilter(value, filter)
                }
                if tag.kind == "v" || tag.kind == "&" {
                    let text = try stringify(value)
                    result += tag.kind == "v" ? escape(text) : text
                } else {
                    if tag.kind == "^" {
                        if !truthy(value) {
                            result += try render(
                                tags,
                                at + 1,
                                tag.end,
                                contexts,
                                loops,
                                partials,
                                strict,
                                depth
                            )
                        }
                    } else if case .list(let list) = value {
                        for (i, item) in list.enumerated() {
                            result += try render(
                                tags,
                                at + 1,
                                tag.end,
                                contexts + [item],
                                loops + [(i, list.count)],
                                partials,
                                strict,
                                depth
                            )
                        }
                    } else if truthy(value) {
                        result += try render(
                            tags,
                            at + 1,
                            tag.end,
                            contexts + [value],
                            loops,
                            partials,
                            strict,
                            depth
                        )
                    }
                    at = tag.end
                }
            case ">":
                guard let source = partials[tag.text] else {
                    throw Problem(reason: "unknown partial '\(tag.text)'")
                }
                guard depth < 8 else {
                    throw Problem(reason: "partial depth exceeded at '\(tag.text)'")
                }
                let lines = source.map { SourceLine(line: $0.line, text: $0.text.isEmpty ? "" : tag.indent + $0.text) }
                let parsed = try analyze(lines)
                result += try render(parsed, 0, parsed.count, contexts, loops, partials, strict, depth + 1)
            default:
                break
            }
        } catch let error as Problem {
            throw Problem(line: error.line == 0 ? tag.line : error.line, reason: error.reason)
        }
        at += 1
    }
    return result
}
func dump(_ v: Value, _ path: String, _ leaves: inout [String]) {
    switch v {
    case .map(let map) where !map.isEmpty:
        for key in map.keys.sorted() {
            dump(map[key]!, path.isEmpty ? key : path + "." + key, &leaves)
        }
    case .list(let list) where !list.isEmpty:
        for (i, value) in list.enumerated() {
            dump(value, "\(path)[\(i)]", &leaves)
        }
    default:
        guard !path.isEmpty else {
            return
        }
        let notation: String
        switch v {
        case .string(let s):
            notation = "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
                of: "\"",
                with: "\\\""
            ).replacingOccurrences(of: "\n", with: "\\n") + "\""
        case .list:
            notation = "[]"
        case .map:
            notation = "{}"
        default:
            notation = try! stringify(v)
        }
        leaves.append(path + " = " + notation)
    }
}
func outputTemplate(
    _ name: String,
    _ source: [SourceLine],
    _ root: Value,
    _ partials: [String: [SourceLine]],
    _ strict: Bool
) {
    do {
        let tags = try analyze(source), text = try render(tags, 0, tags.count, [root], [], partials, strict, 0)
        let count = text.isEmpty ? 0 : text.filter { $0 == "\n" }.count + (text.hasSuffix("\n") ? 0 : 1)
        print("TEMPLATE \(name) OK lines=\(count) chars=\(text.utf8.count)")
        if !text.isEmpty {
            print(text, terminator: text.hasSuffix("\n") ? "" : "\n")
        }
    } catch let error as Problem { print("TEMPLATE \(name) ERROR line \(error.line): \(error.reason)") }
    catch { fatalError("unexpected error") }
}

var lines: [String] = []
while let line = readLine() {
    lines.append(line)
}
var at = 0, root = Value.map([:]), partials: [String: [SourceLine]] = [:], templates: [String: [SourceLine]] = [:],
    strict = false
while at < lines.count {
    let command = lines[at], number = at + 1
    at += 1
    if command == "END" {
        break
    }
    if command == "DATA" {
        var set = 0, unset = 0, errors: [String] = []
        while lines[at] != "ENDDATA" {
            let line = lines[at], lineNumber = at + 1
            at += 1
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            do {
                let deletion = line.hasPrefix("UNSET "), key: String, notation: String?
                if deletion {
                    key = cut(line, 6)
                    notation = nil
                } else {
                    guard let pos = find(line, " = ") else {
                        throw Problem(reason: "bad line")
                    }
                    key = cut(line, 0, pos)
                    notation = cut(line, pos + 3)
                }
                guard let parts = keyParts(key) else {
                    throw Problem(reason: "bad key '\(key)'")
                }
                if let notation {
                    guard let value = parseValue(notation) else {
                        throw Problem(reason: "bad value '\(notation)'")
                    }
                    root = try assigning(root, parts[...], value)
                    set += 1
                } else {
                    guard let value = removing(root, parts[...]) else {
                        throw Problem(reason: "no value at '\(key)'")
                    }
                    root = value
                    unset += 1
                }
            } catch let error as Problem { errors.append("ERROR line \(lineNumber): \(error.reason)") }
            catch { fatalError("unexpected error") }
        }
        at += 1
        print("DATA set=\(set) unset=\(unset) errors=\(errors.count)")
        for error in errors {
            print(error)
        }
    } else if command.hasPrefix("PARTIAL ") || command.hasPrefix("TEMPLATE ") {
        let partial = command.hasPrefix("PARTIAL "), name = command.components(separatedBy: " ")[1]
        let end = partial ? "ENDPARTIAL" : "ENDTEMPLATE"
        var source: [SourceLine] = []
        while lines[at] != end {
            source.append(SourceLine(line: at + 1, text: lines[at]))
            at += 1
        }
        at += 1
        if partial {
            do {
                _ = try analyze(source)
                print("PARTIAL \(name) \(partials[name] == nil ? "DEFINED" : "REPLACED") lines=\(source.count)")
                partials[name] = source
            } catch let error as Problem { print("PARTIAL \(name) ERROR line \(error.line): \(error.reason)") }
            catch { fatalError("unexpected error") }
        } else {
            templates[name] = source
            outputTemplate(name, source, root, partials, strict)
        }
    } else if command.hasPrefix("RENDER ") {
        let name = cut(command, 7)
        if let source = templates[name] {
            outputTemplate(name, source, root, partials, strict)
        } else {
            print("TEMPLATE \(name) ERROR line \(number): unknown template '\(name)'")
        }
    } else if command == "DUMP" {
        var leaves: [String] = []
        dump(root, "", &leaves)
        print("DUMP leaves=\(leaves.count)")
        for leaf in leaves {
            print(leaf)
        }
    } else if command == "RESET" {
        root = .map([:])
        partials.removeAll()
        templates.removeAll()
        print("RESET")
    } else {
        strict = command == "STRICT ON"
        print(command)
    }
}

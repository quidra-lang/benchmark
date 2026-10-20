enum Kind: String, CaseIterable { case string, list, hash, set, zset }
enum Value {
    case string(String), list([String]), hash([String: String]), set(Set<String>), zset([String: Int])
    var kind: Kind {
        switch self {
        case .string: return .string
        case .list: return .list
        case .hash: return .hash
        case .set: return .set
        case .zset: return .zset
        }
    }
    var emptyCollection: Bool {
        switch self {
        case .string: return false
        case .list(let values): return values.isEmpty
        case .hash(let values): return values.isEmpty
        case .set(let values): return values.isEmpty
        case .zset(let values): return values.isEmpty
        }
    }
}
struct Record { var value: Value; var expiry: Int? }
typealias Database = [String: Record]
typealias Reply = [String]
struct CommandError: Error { let message: String }
let wrongType = "WRONGTYPE Operation against a key holding the wrong kind of value"
let notInteger = "ERR value is not an integer or out of range"
let overflow = "ERR increment or decrement would overflow"
let syntax = "ERR syntax error"
let positive = "ERR value is out of range, must be positive"
let noKey = "ERR no such key"
func fail(_ message: String) throws -> Never { throw CommandError(message: message) }

func number(_ word: String, message: String = notInteger) throws -> Int {
    if word == "0" { return 0 }
    let bytes = Array(word.utf8)
    guard !bytes.isEmpty else { try fail(message) }
    let start = bytes[0] == 45 ? 1 : 0, count = bytes.count - start
    guard (1...9).contains(count), (49...57).contains(bytes[start]) else { try fail(message) }
    var result = 0
    for byte in bytes[start...] {
        guard (48...57).contains(byte) else { try fail(message) }
        result = result * 10 + Int(byte - 48)
    }
    return start == 1 ? -result : result
}
func increment(_ value: Int, by delta: Int) throws -> Int {
    let result = value + delta
    guard (-999999999...999999999).contains(result) else { try fail(overflow) }
    return result
}
func quote(_ value: String) -> String {
    var output = "\""
    for character in value {
        if character == "\"" || character == "\\" { output += "\\" }
        output.append(character)
    }
    return output + "\""
}
func integer(_ value: Int) -> Reply { ["(integer) \(value)"] }
func stringReply(_ value: String?) -> Reply { [value.map(quote) ?? "(nil)"] }
func arrayReply(_ values: [String?]) -> Reply {
    guard !values.isEmpty else { return ["(empty array)"] }
    let width = String(values.count).count
    return values.enumerated().map { index, value in
        let label = String(index + 1)
        return String(repeating: " ", count: width - label.count) + label + ") " + stringReply(value)[0]
    }
}
func arrayReply(_ values: [String]) -> Reply { arrayReply(values.map { Optional($0) }) }
func range<T>(_ values: [T], _ first: Int, _ last: Int) -> [T] {
    let start = max(0, first < 0 ? first + values.count : first)
    let stop = min(values.count - 1, last < 0 ? last + values.count : last)
    return start <= stop ? Array(values[start...stop]) : []
}
func splitArguments(_ line: String) -> [String]? {
    let bytes = Array(line.utf8)
    var position = 0, arguments: [String] = []
    while position < bytes.count {
        if bytes[position] == 32 { position += 1; continue }
        if bytes[position] != 34 {
            let start = position
            while position < bytes.count && bytes[position] != 32 { position += 1 }
            arguments.append(String(decoding: bytes[start..<position], as: UTF8.self))
            continue
        }
        position += 1
        var value: [UInt8] = [], closed = false
        while position < bytes.count {
            let byte = bytes[position]
            position += 1
            if byte == 34 { closed = true; break }
            if byte == 92 {
                guard position < bytes.count, bytes[position] == 34 || bytes[position] == 92 else { return nil }
                value.append(bytes[position]); position += 1
            } else { value.append(byte) }
        }
        guard closed, position == bytes.count || bytes[position] == 32 else { return nil }
        arguments.append(String(decoding: value, as: UTF8.self))
    }
    return arguments
}

enum PatternPart { case literal(UInt8), any, star, characterClass(Set<UInt8>, negated: Bool) }
func parsePattern(_ pattern: String) throws -> [PatternPart] {
    let bytes = Array(pattern.utf8)
    var parts: [PatternPart] = [], position = 0
    while position < bytes.count {
        let byte = bytes[position]
        if byte == 92 {
            position += 1
            guard position < bytes.count else { try fail("ERR invalid pattern") }
            parts.append(.literal(bytes[position]))
        } else if byte == 91 {
            guard let end = bytes[(position + 1)...].firstIndex(of: 93) else { try fail("ERR invalid pattern") }
            var index = position + 1
            let negated = index < end && bytes[index] == 94
            if negated { index += 1 }
            guard index < end else { try fail("ERR invalid pattern") }
            var characters = Set<UInt8>()
            while index < end {
                if index + 2 < end && bytes[index + 1] == 45 {
                    let first = min(bytes[index], bytes[index + 2]), last = max(bytes[index], bytes[index + 2])
                    characters.formUnion(first...last); index += 3
                } else { characters.insert(bytes[index]); index += 1 }
            }
            parts.append(.characterClass(characters, negated: negated)); position = end
        } else if byte == 42 { parts.append(.star) }
        else if byte == 63 { parts.append(.any) }
        else { parts.append(.literal(byte)) }
        position += 1
    }
    return parts
}
func matches(_ parts: [PatternPart], _ string: String) -> Bool {
    let bytes = Array(string.utf8)
    var previous = [Bool](repeating: false, count: bytes.count + 1)
    previous[0] = true
    for part in parts {
        var current = [Bool](repeating: false, count: bytes.count + 1)
        if case .star = part {
            current[0] = previous[0]
            for index in bytes.indices { current[index + 1] = previous[index + 1] || current[index] }
        } else {
            for index in bytes.indices {
                let accepts: Bool
                switch part {
                case .literal(let byte): accepts = byte == bytes[index]
                case .any: accepts = true
                case .characterClass(let characters, let negated): accepts = characters.contains(bytes[index]) != negated
                case .star: accepts = false
                }
                current[index + 1] = previous[index] && accepts
            }
        }
        previous = current
    }
    return previous[bytes.count]
}
enum Bound {
    case negativeInfinity, positiveInfinity, finite(Int, inclusive: Bool)
    func accepts(_ score: Int, lower: Bool) -> Bool {
        switch self {
        case .negativeInfinity: return lower
        case .positiveInfinity: return !lower
        case .finite(let value, let inclusive):
            return lower ? (inclusive ? score >= value : score > value) : (inclusive ? score <= value : score < value)
        }
    }
}
func scoreBound(_ word: String) throws -> Bound {
    if word == "-inf" { return .negativeInfinity }
    if word == "+inf" { return .positiveInfinity }
    let inclusive = word.first != "("
    let value = try number(inclusive ? word : String(word.dropFirst()), message: "ERR min or max is not a float")
    return .finite(value, inclusive: inclusive)
}

enum Group { case text, lists, hashes, sets, sortedSets, keys, control }
struct CommandSpec { let group: Group; let minimum: Int; let maximum: Int?; let parity: Int? }
let commands: [String: CommandSpec] = {
    var result: [String: CommandSpec] = [:]
    func add(_ group: Group, _ names: String, _ minimum: Int, _ maximum: Int?, parity: Int? = nil) {
        for name in names.split(separator: " ") {
            result[String(name)] = CommandSpec(group: group, minimum: minimum, maximum: maximum, parity: parity)
        }
    }
    add(.text, "SET", 2, nil)
    add(.text, "GET INCR DECR STRLEN", 1, 1)
    add(.text, "MSET", 2, nil, parity: 0)
    add(.text, "MGET", 1, nil)
    add(.text, "INCRBY DECRBY APPEND", 2, 2)
    add(.text, "GETRANGE", 3, 3)
    add(.lists, "LPUSH RPUSH", 2, nil)
    add(.lists, "LPOP RPOP", 1, 2)
    add(.lists, "LRANGE LSET LREM LTRIM", 3, 3)
    add(.lists, "LLEN", 1, 1)
    add(.lists, "LINDEX", 2, 2)
    add(.lists, "LINSERT", 4, 4)
    add(.hashes, "HSET", 3, nil, parity: 1)
    add(.hashes, "HGET HEXISTS", 2, 2)
    add(.hashes, "HDEL", 2, nil)
    add(.hashes, "HGETALL HLEN HKEYS HVALS", 1, 1)
    add(.hashes, "HINCRBY", 3, 3)
    add(.sets, "SADD SREM", 2, nil)
    add(.sets, "SISMEMBER", 2, 2)
    add(.sets, "SMEMBERS SCARD", 1, 1)
    add(.sets, "SINTER SUNION SDIFF", 1, nil)
    add(.sets, "SINTERSTORE SUNIONSTORE SDIFFSTORE", 2, nil)
    add(.sortedSets, "ZADD", 3, nil, parity: 1)
    add(.sortedSets, "ZSCORE ZRANK", 2, 2)
    add(.sortedSets, "ZINCRBY", 3, 3)
    add(.sortedSets, "ZREM", 2, nil)
    add(.sortedSets, "ZCARD", 1, 1)
    add(.sortedSets, "ZRANGE ZRANGEBYSCORE", 3, 4)
    add(.keys, "DEL EXISTS", 1, nil)
    add(.keys, "TYPE KEYS TTL PERSIST TICK", 1, 1)
    add(.keys, "RENAME RENAMENX", 2, 2)
    add(.keys, "EXPIRE", 2, 3)
    add(.keys, "TIME DBSIZE FLUSH INFO", 0, 0)
    add(.control, "BEGIN COMMIT ROLLBACK", 0, 0)
    add(.control, "SNAPSHOT RESTORE", 1, 1)
    return result
}()

struct Store {
    private var database: Database = [:]
    private var time = 0
    private var transactions: [Database] = []
    private var snapshots: [String: Database] = [:]

    private func text(_ key: String) throws -> String {
        guard let value = database[key]?.value else { return "" }
        guard case .string(let content) = value else { try fail(wrongType) }
        return content
    }
    private func list(_ key: String) throws -> [String] {
        guard let value = database[key]?.value else { return [] }
        guard case .list(let content) = value else { try fail(wrongType) }
        return content
    }
    private func hash(_ key: String) throws -> [String: String] {
        guard let value = database[key]?.value else { return [:] }
        guard case .hash(let content) = value else { try fail(wrongType) }
        return content
    }
    private func members(_ key: String) throws -> Set<String> {
        guard let value = database[key]?.value else { return [] }
        guard case .set(let content) = value else { try fail(wrongType) }
        return content
    }
    private func scores(_ key: String) throws -> [String: Int] {
        guard let value = database[key]?.value else { return [:] }
        guard case .zset(let content) = value else { try fail(wrongType) }
        return content
    }
    private mutating func replace(_ key: String, _ value: Value, expiry: Int? = nil) {
        if value.emptyCollection { database.removeValue(forKey: key) }
        else { database[key] = Record(value: value, expiry: expiry) }
    }
    private mutating func update(_ key: String, _ value: Value) {
        replace(key, value, expiry: database[key]?.expiry)
    }
    private mutating func purge() -> Int {
        let expired = database.keys.filter { database[$0]!.expiry.map { $0 <= time } ?? false }
        for key in expired { database.removeValue(forKey: key) }
        return expired.count
    }
    private mutating func textCommand(_ command: String, _ args: [String]) throws -> Reply {
        let key = args[0]
        if command == "SET" {
            var options = Set<String>(), secondsWord: String?
            var index = 2
            while index < args.count {
                let option = args[index].uppercased()
                guard ["NX", "XX", "EX", "KEEPTTL", "GET"].contains(option), options.insert(option).inserted else { try fail(syntax) }
                if option == "EX" {
                    index += 1
                    guard index < args.count else { try fail(syntax) }
                    secondsWord = args[index]
                }
                index += 1
            }
            if (options.contains("NX") && options.contains("XX")) || (options.contains("EX") && options.contains("KEEPTTL")) { try fail(syntax) }
            var expiry: Int?
            if let secondsWord {
                let seconds = try number(secondsWord)
                guard seconds > 0 else { try fail("ERR invalid expire time in 'set' command") }
                expiry = time + seconds
            }
            let exists = database[key] != nil
            var old: String?
            if options.contains("GET") {
                let value = try text(key)
                if exists { old = value }
            }
            if options.contains("KEEPTTL") && exists { expiry = database[key]!.expiry }
            let changed = !(options.contains("NX") && exists) && !(options.contains("XX") && !exists)
            if changed { replace(key, .string(args[1]), expiry: expiry) }
            if options.contains("GET") { return stringReply(old) }
            return changed ? ["OK"] : stringReply(nil)
        }
        if command == "MSET" {
            for index in stride(from: 0, to: args.count, by: 2) { replace(args[index], .string(args[index + 1])) }
            return ["OK"]
        }
        if command == "MGET" {
            let output: [String?] = args.map { key in
                guard let record = database[key], case .string(let value) = record.value else { return nil }
                return value
            }
            return arrayReply(output)
        }
        if ["INCR", "DECR", "INCRBY", "DECRBY"].contains(command) {
            var delta = args.count == 2 ? try number(args[1]) : 1
            if command == "DECR" || command == "DECRBY" { delta = -delta }
            let value = try text(key)
            let old = database[key] == nil ? 0 : try number(value)
            let result = try increment(old, by: delta)
            update(key, .string(String(result)))
            return integer(result)
        }
        if command == "GETRANGE" {
            let start = try number(args[1]), stop = try number(args[2])
            let value = try text(key)
            return stringReply(String(decoding: range(Array(value.utf8), start, stop), as: UTF8.self))
        }
        var value = try text(key)
        if command == "GET" { return stringReply(database[key] == nil ? nil : value) }
        if command == "STRLEN" { return integer(value.count) }
        value += args[1]
        update(key, .string(value))
        return integer(value.count)
    }
    private mutating func listCommand(_ command: String, _ args: [String]) throws -> Reply {
        let key = args[0]
        if command == "LPOP" || command == "RPOP" {
            let counted = args.count == 2
            let count = counted ? try number(args[1], message: positive) : 1
            guard count >= 0 else { try fail(positive) }
            var values = try list(key)
            guard database[key] != nil else { return stringReply(nil) }
            var removed: [String] = []
            for _ in 0..<min(count, values.count) {
                removed.append(command == "LPOP" ? values.removeFirst() : values.removeLast())
            }
            update(key, .list(values))
            return counted ? arrayReply(removed) : stringReply(removed[0])
        }
        if command == "LRANGE" || command == "LTRIM" {
            let start = try number(args[1]), stop = try number(args[2])
            let values = range(try list(key), start, stop)
            if command == "LRANGE" { return arrayReply(values) }
            update(key, .list(values))
            return ["OK"]
        }
        if command == "LINDEX" || command == "LSET" {
            var index = try number(args[1])
            var values = try list(key)
            if index < 0 { index += values.count }
            let inside = values.indices.contains(index)
            if command == "LINDEX" { return stringReply(inside ? values[index] : nil) }
            guard database[key] != nil else { try fail(noKey) }
            guard inside else { try fail("ERR index out of range") }
            values[index] = args[2]
            update(key, .list(values))
            return ["OK"]
        }
        if command == "LREM" {
            let count = try number(args[1])
            var values = try list(key)
            if count < 0 { values.reverse() }
            let limit = count == 0 ? values.count : abs(count)
            var removed = 0, kept: [String] = []
            for value in values {
                if value == args[2] && removed < limit { removed += 1 }
                else { kept.append(value) }
            }
            if count < 0 { kept.reverse() }
            update(key, .list(kept))
            return integer(removed)
        }
        if command == "LINSERT" {
            let whereTo = args[1].uppercased()
            guard whereTo == "BEFORE" || whereTo == "AFTER" else { try fail(syntax) }
            var values = try list(key)
            guard database[key] != nil else { return integer(0) }
            guard let pivot = values.firstIndex(of: args[2]) else { return integer(-1) }
            values.insert(args[3], at: pivot + (whereTo == "AFTER" ? 1 : 0))
            update(key, .list(values))
            return integer(values.count)
        }
        var values = try list(key)
        if command == "LLEN" { return integer(values.count) }
        for value in args.dropFirst() {
            if command == "LPUSH" { values.insert(value, at: 0) }
            else { values.append(value) }
        }
        update(key, .list(values))
        return integer(values.count)
    }
    private mutating func hashCommand(_ command: String, _ args: [String]) throws -> Reply {
        let key = args[0]
        if command == "HINCRBY" {
            let delta = try number(args[2])
            var fields = try hash(key)
            let old = try fields[args[1]].map { try number($0, message: "ERR hash value is not an integer") } ?? 0
            let result = try increment(old, by: delta)
            fields[args[1]] = String(result)
            update(key, .hash(fields))
            return integer(result)
        }
        var fields = try hash(key)
        if command == "HSET" {
            var added = 0
            for index in stride(from: 1, to: args.count, by: 2) {
                if fields[args[index]] == nil { added += 1 }
                fields[args[index]] = args[index + 1]
            }
            update(key, .hash(fields))
            return integer(added)
        }
        if command == "HGET" { return stringReply(fields[args[1]]) }
        if command == "HDEL" {
            var removed = 0
            for field in args.dropFirst() { if fields.removeValue(forKey: field) != nil { removed += 1 } }
            update(key, .hash(fields))
            return integer(removed)
        }
        if command == "HLEN" { return integer(fields.count) }
        if command == "HEXISTS" { return integer(fields[args[1]] == nil ? 0 : 1) }
        var output: [String] = []
        for field in fields.keys.sorted() {
            if command != "HVALS" { output.append(field) }
            if command != "HKEYS" { output.append(fields[field]!) }
        }
        return arrayReply(output)
    }
    private mutating func setCommand(_ command: String, _ args: [String]) throws -> Reply {
        let storing = command.hasSuffix("STORE")
        let operation = storing ? String(command.dropLast(5)) : command
        if ["SINTER", "SUNION", "SDIFF"].contains(operation) {
            let keys = storing ? Array(args.dropFirst()) : args
            let sources = try keys.map { try members($0) }
            var result = sources[0]
            for source in sources.dropFirst() {
                if operation == "SINTER" { result.formIntersection(source) }
                else if operation == "SUNION" { result.formUnion(source) }
                else { result.subtract(source) }
            }
            if storing { replace(args[0], .set(result)); return integer(result.count) }
            return arrayReply(result.sorted())
        }
        var values = try members(args[0])
        if command == "SCARD" { return integer(values.count) }
        if command == "SMEMBERS" { return arrayReply(values.sorted()) }
        if command == "SISMEMBER" { return integer(values.contains(args[1]) ? 1 : 0) }
        var changed = 0
        for member in args.dropFirst() {
            if command == "SADD" { if values.insert(member).inserted { changed += 1 } }
            else if values.remove(member) != nil { changed += 1 }
        }
        update(args[0], .set(values))
        return integer(changed)
    }
    private mutating func sortedSetCommand(_ command: String, _ args: [String]) throws -> Reply {
        let key = args[0]
        if command == "ZADD" {
            let parsedScores = try stride(from: 1, to: args.count, by: 2).map { try number(args[$0]) }
            var values = try scores(key), added = 0
            for index in parsedScores.indices {
                let member = args[2 * index + 2]
                if values[member] == nil { added += 1 }
                values[member] = parsedScores[index]
            }
            update(key, .zset(values))
            return integer(added)
        }
        if command == "ZINCRBY" {
            let delta = try number(args[1])
            var values = try scores(key)
            let result = try increment(values[args[2]] ?? 0, by: delta)
            values[args[2]] = result
            update(key, .zset(values))
            return stringReply(String(result))
        }
        let byIndex = command == "ZRANGE", byScore = command == "ZRANGEBYSCORE"
        let withScores = args.count == 4
        var start = 0, stop = 0
        var minimum = Bound.negativeInfinity, maximum = Bound.positiveInfinity
        if byIndex || byScore {
            if withScores && args[3].uppercased() != "WITHSCORES" { try fail(syntax) }
            if byIndex { start = try number(args[1]); stop = try number(args[2]) }
            else { minimum = try scoreBound(args[1]); maximum = try scoreBound(args[2]) }
        }
        var values = try scores(key)
        if command == "ZSCORE" { return stringReply(values[args[1]].map { String($0) }) }
        if command == "ZREM" {
            var removed = 0
            for member in args.dropFirst() { if values.removeValue(forKey: member) != nil { removed += 1 } }
            update(key, .zset(values))
            return integer(removed)
        }
        if command == "ZCARD" { return integer(values.count) }
        var ordered = values.sorted { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }
        if command == "ZRANK" {
            if let index = ordered.firstIndex(where: { $0.key == args[1] }) { return integer(index) }
            return stringReply(nil)
        }
        if byIndex { ordered = range(ordered, start, stop) }
        var output: [String] = []
        for (member, score) in ordered {
            if byScore && (!minimum.accepts(score, lower: true) || !maximum.accepts(score, lower: false)) { continue }
            output.append(member)
            if withScores { output.append(String(score)) }
        }
        return arrayReply(output)
    }
    private mutating func keyCommand(_ command: String, _ args: [String]) throws -> Reply {
        if command == "DEL" || command == "EXISTS" {
            var count = 0
            for key in args {
                if command == "DEL" { if database.removeValue(forKey: key) != nil { count += 1 } }
                else if database[key] != nil { count += 1 }
            }
            return integer(count)
        }
        if command == "KEYS" {
            let pattern = try parsePattern(args[0])
            return arrayReply(database.keys.filter { matches(pattern, $0) }.sorted())
        }
        if command == "EXPIRE" {
            let condition = args.count == 3 ? args[2].uppercased() : ""
            if args.count == 3 && !["NX", "XX", "GT", "LT"].contains(condition) { try fail("ERR Unsupported option \(args[2])") }
            let seconds = try number(args[1])
            guard let record = database[args[0]] else { return integer(0) }
            let old = record.expiry, expiry = time + seconds
            if (condition == "NX" && old != nil) || (condition == "XX" && old == nil)
                || (condition == "GT" && (old == nil || expiry <= old!))
                || (condition == "LT" && old != nil && expiry >= old!) { return integer(0) }
            if seconds <= 0 { database.removeValue(forKey: args[0]) }
            else { database[args[0]]!.expiry = expiry }
            return integer(1)
        }
        if command == "TICK" {
            let seconds = try number(args[0])
            guard seconds > 0 else { try fail(positive) }
            time += seconds
            return integer(purge())
        }
        if command == "TIME" { return integer(time) }
        if command == "DBSIZE" { return integer(database.count) }
        if command == "FLUSH" { database.removeAll(); return ["OK"] }
        if command == "INFO" {
            let expires = database.values.filter { $0.expiry != nil }.count
            var parts = ["keys=\(database.count)", "expires=\(expires)"]
            for kind in Kind.allCases {
                parts.append("\(kind.rawValue)=\(database.values.filter { $0.value.kind == kind }.count)")
            }
            parts += ["time=\(time)", "depth=\(transactions.count)", "snapshots=\(snapshots.count)"]
            return [parts.joined(separator: ",")]
        }
        let key = args[0]
        if command == "TYPE" { return [database[key]?.value.kind.rawValue ?? "none"] }
        if command == "TTL" {
            guard let record = database[key] else { return integer(-2) }
            return integer(record.expiry.map { $0 - time } ?? -1)
        }
        if command == "PERSIST" {
            guard database[key]?.expiry != nil else { return integer(0) }
            database[key]!.expiry = nil
            return integer(1)
        }
        guard let record = database[key] else { try fail(noKey) }
        if command == "RENAMENX" && database[args[1]] != nil { return integer(0) }
        if key != args[1] { database[args[1]] = record; database.removeValue(forKey: key) }
        return command == "RENAME" ? ["OK"] : integer(1)
    }
    private mutating func controlCommand(_ command: String, _ args: [String]) throws -> Reply {
        if command == "BEGIN" { transactions.append(database); return ["OK"] }
        if command == "COMMIT" || command == "ROLLBACK" {
            guard let saved = transactions.popLast() else { try fail("ERR no transaction") }
            if command == "ROLLBACK" { database = saved; _ = purge() }
            return ["OK"]
        }
        if command == "SNAPSHOT" { snapshots[args[0]] = database; return ["OK"] }
        guard let saved = snapshots[args[0]] else { try fail("ERR no such snapshot") }
        database = saved
        _ = purge()
        return ["OK"]
    }
    mutating func execute(_ line: String) throws -> Reply {
        guard let parsed = splitArguments(line), let original = parsed.first else { return ["Invalid argument(s)"] }
        let command = original.uppercased(), args = Array(parsed.dropFirst())
        guard let specification = commands[command] else { try fail("ERR unknown command '\(original)'") }
        if args.count < specification.minimum || (specification.maximum.map { args.count > $0 } ?? false)
            || (specification.parity.map { args.count % 2 != $0 } ?? false) {
            try fail("ERR wrong number of arguments for '\(command.lowercased())' command")
        }
        switch specification.group {
        case .text: return try textCommand(command, args)
        case .lists: return try listCommand(command, args)
        case .hashes: return try hashCommand(command, args)
        case .sets: return try setCommand(command, args)
        case .sortedSets: return try sortedSetCommand(command, args)
        case .keys: return try keyCommand(command, args)
        case .control: return try controlCommand(command, args)
        }
    }
}

if let first = readLine(), let count = Int(first) {
    var store = Store()
    for _ in 0..<count {
        guard let line = readLine() else { break }
        do {
            for output in try store.execute(line) { print(output) }
        } catch let problem as CommandError {
            print("(error) \(problem.message)")
        } catch {
            fatalError("unexpected command error")
        }
    }
}

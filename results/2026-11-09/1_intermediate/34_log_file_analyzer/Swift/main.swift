import Foundation

let methods = ["GET", "HEAD", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]
let reasons = ["fields", "date", "time", "ip", "method", "path", "status", "bytes", "latency"]
let statusClasses = ["1xx", "2xx", "3xx", "4xx", "5xx"]
let filterKeys = ["METHOD", "STATUS", "IP", "PATH"]
let forms: [String: [String]] = [
    "SUMMARY": [], "MALFORMED": [], "STATUS": [], "METHODS": [],
    "TOP": ["kind", "limit"], "HOURLY": [], "TIMELINE": ["minutes"],
    "BANDWIDTH": [], "VISITORS": [], "LATENCY": ["path"],
    "HISTOGRAM": ["width"], "APDEX": ["threshold"], "ERRORS": [],
    "SLOWEST": ["limit"], "SESSIONS": ["ip", "minutes"],
    "BURST": ["length", "times"], "PEAK": ["length"], "GAPS": ["length"],
    "IP": ["ip"], "RANGE": ["date", "time", "date", "time"],
    "FILTER": ["key", "value"], "UNFILTER": ["subject"], "RESET": [], "STATE": []
]
let requireRecords: Set<String> = [
    "STATUS", "METHODS", "TOP", "HOURLY", "TIMELINE", "BANDWIDTH", "VISITORS",
    "HISTOGRAM", "APDEX", "ERRORS", "SLOWEST", "BURST", "PEAK", "GAPS"
]
let ranges: [String: ClosedRange<Int>] = [
    "limit": 1...100, "minutes": 1...1440, "width": 1...100000,
    "threshold": 1...100000, "length": 1...86400, "times": 1...1000
]
let argumentErrors = [
    "limit": "invalid number", "minutes": "invalid number", "width": "invalid number",
    "threshold": "invalid number", "length": "invalid number", "times": "invalid number",
    "kind": "invalid kind", "path": "invalid path", "ip": "invalid ip",
    "date": "invalid timestamp", "time": "invalid timestamp", "key": "invalid key",
    "subject": "invalid key", "value": "invalid value"
]
let calendar: Calendar = {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(secondsFromGMT: 0)!
    return value
}()
let epoch = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1))!

struct QueryError: Error {
    let message: String
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw QueryError(message: message) }
}

func words(_ line: String) -> [String] {
    line.split(separator: " ").map(String.init)
}

func matches(_ text: String, _ pattern: String) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
}

func canonical(_ text: String, _ maximum: Int) -> Bool {
    text.utf8.count <= maximum && matches(text, "^(0|[1-9][0-9]*)$")
}

func parseDate(_ text: String) -> Date? {
    guard matches(text, "^[0-9]{4}-[0-9]{2}-[0-9]{2}$") else { return nil }
    let parts = text.split(separator: "-").map { Int($0)! }
    guard (2000...2059).contains(parts[0]), (1...12).contains(parts[1]),
          (1...31).contains(parts[2]),
          let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    else { return nil }
    let actual = calendar.dateComponents([.year, .month, .day], from: date)
    return actual.year == parts[0] && actual.month == parts[1] && actual.day == parts[2] ? date : nil
}

func validTime(_ text: String) -> Bool {
    guard matches(text, "^[0-9]{2}:[0-9]{2}:[0-9]{2}$") else { return false }
    let parts = text.split(separator: ":").map { Int($0)! }
    return parts[0] < 24 && parts[1] < 60 && parts[2] < 60
}

func validIP(_ text: String) -> Bool {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    return parts.count == 4 && parts.allSatisfy { canonical($0, 3) && Int($0)! <= 255 }
}

func validStatus(_ text: String) -> Bool {
    matches(text, "^[0-9]{3}$") && (100...599).contains(Int(text)!)
}

func validFilter(_ key: String, _ value: String) -> Bool {
    switch key {
    case "METHOD": return methods.contains(value)
    case "STATUS": return statusClasses.contains(value) || validStatus(value)
    case "IP": return validIP(value)
    default: return value.hasPrefix("/")
    }
}

func validArgument(_ kind: String, _ value: String, _ arguments: [String]) -> Bool {
    if let range = ranges[kind] { return canonical(value, 6) && range.contains(Int(value)!) }
    switch kind {
    case "kind": return value == "PATHS" || value == "IPS"
    case "path": return value.hasPrefix("/")
    case "ip": return validIP(value)
    case "date": return parseDate(value) != nil
    case "time": return validTime(value)
    case "key": return filterKeys.contains(value)
    case "subject": return value == "RANGE" || filterKeys.contains(value)
    default: return validFilter(arguments[0], value)
    }
}

func malformedReason(_ fields: [String]) -> String? {
    if fields.count != 8 { return "fields" }
    if parseDate(fields[0]) == nil { return "date" }
    if !validTime(fields[1]) { return "time" }
    if !validIP(fields[2]) { return "ip" }
    if !methods.contains(fields[3]) { return "method" }
    if !fields[4].hasPrefix("/") { return "path" }
    if !validStatus(fields[5]) { return "status" }
    if !canonical(fields[6], 8) { return "bytes" }
    if !canonical(fields[7], 6) { return "latency" }
    return nil
}

func secondsOf(_ date: String, _ time: String) -> Int {
    let days = calendar.dateComponents([.day], from: epoch, to: parseDate(date)!).day!
    let parts = time.split(separator: ":").map { Int($0)! }
    return days * 86400 + parts[0] * 3600 + parts[1] * 60 + parts[2]
}

func intervalLabel(_ seconds: Int) -> String {
    let date = calendar.date(byAdding: .day, value: seconds / 86400, to: epoch)!
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d %02d:%02d", parts.year!, parts.month!, parts.day!,
                  seconds % 86400 / 3600, seconds % 3600 / 60)
}

func normalizePath(_ text: String) -> String {
    let raw = String(text.prefix { $0 != "?" })
    var parts: [String] = []
    for part in raw.split(separator: "/") {
        if part == ".." {
            if !parts.isEmpty { parts.removeLast() }
        } else if part != "." {
            parts.append(String(part))
        }
    }
    return "/" + parts.map { part in
        if matches(part, "^[0-9]+$") { return "{id}" }
        if part.count >= 8 && matches(part, "^[0-9a-f]+$") && matches(part, "[0-9]") { return "{hex}" }
        return part
    }.joined(separator: "/")
}

func ipNumber(_ text: String) -> Int {
    text.split(separator: ".").reduce(0) { $0 * 256 + Int($1)! }
}

func statusMatches(_ value: String, _ status: Int) -> Bool {
    statusClasses.contains(value) ? status / 100 == Int(value.prefix(1))! : status == Int(value)!
}

func decimal(_ numerator: Int, _ denominator: Int, _ places: Int) -> String {
    let scale = [10, 100, 1000][places - 1]
    let value = numerator * scale / denominator
    let digits = String(value % scale)
    return "\(value / scale)." + String(repeating: "0", count: places - digits.count) + digits
}

func percent(_ part: Int, _ total: Int) -> String {
    decimal(part * 100, total, 2) + "%"
}

func bytesText(_ count: Int) -> String {
    for (unit, suffix) in [(1073741824, "GB"), (1048576, "MB"), (1024, "KB")] {
        if count >= unit { return decimal(count, unit, 1) + suffix }
    }
    return "\(count)B"
}

func frequencies<T: Hashable>(_ values: [T]) -> [T: Int] {
    Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
}

func ranked(_ counts: [String: Int], ip: Bool = false) -> [String] {
    counts.keys.sorted { left, right in
        if counts[left]! != counts[right]! { return counts[left]! > counts[right]! }
        return ip ? ipNumber(left) < ipNumber(right) : left < right
    }
}

struct LogRecord {
    let line: Int
    let date: String
    let timestamp: String
    let seconds: Int
    let hour: Int
    let ip: String
    let method: String
    let path: String
    let status: Int
    let bytes: Int
    let latency: Int

    init(line: Int, fields: [String]) {
        self.line = line
        date = fields[0]
        timestamp = fields[0] + " " + fields[1]
        seconds = secondsOf(fields[0], fields[1])
        hour = Int(fields[1].prefix(2))!
        ip = fields[2]
        method = fields[3]
        path = normalizePath(fields[4])
        status = Int(fields[5])!
        bytes = Int(fields[6])!
        latency = Int(fields[7])!
    }
}

func sum(_ rows: [LogRecord], _ key: KeyPath<LogRecord, Int>) -> Int {
    rows.reduce(0) { $0 + $1[keyPath: key] }
}

func classCounts(_ rows: [LogRecord]) -> [Int] {
    var counts = Array(repeating: 0, count: 5)
    for row in rows { counts[row.status / 100 - 1] += 1 }
    return counts
}

func buckets(_ values: [Int]) throws -> (first: Int, counts: [Int]) {
    let first = values.min()!, width = values.max()! - first + 1
    try require(width <= 60, "too many buckets")
    var counts = Array(repeating: 0, count: width)
    for value in values { counts[value - first] += 1 }
    return (first, counts)
}

func percentile(_ values: [Int], _ rank: Int) -> Int {
    values[(rank * values.count + 99) / 100 - 1]
}

func peak(_ rows: [LogRecord], _ width: Int) -> (count: Int, first: LogRecord, last: LogRecord) {
    var first = 0, bestFirst = 0, bestLast = 0, count = 0
    for last in rows.indices {
        while rows[last].seconds - rows[first].seconds >= width { first += 1 }
        if last - first + 1 > count {
            count = last - first + 1
            bestFirst = first
            bestLast = last
        }
    }
    return (count, rows[bestFirst], rows[bestLast])
}

struct Apdex {
    let count: Int
    let satisfied: Int
    let tolerating: Int
    var frustrated: Int { count - satisfied - tolerating }
    var points: Int { satisfied * 2 + tolerating }
    var total: Int { count * 2 }
    var text: String { decimal(points, total, 3) }
    var rating: String {
        for (limit, name) in [(94, "excellent"), (85, "good"), (70, "fair"), (50, "poor")] {
            if points * 100 >= total * limit { return name }
        }
        return "unacceptable"
    }
    init(_ rows: [LogRecord], _ threshold: Int) {
        count = rows.count
        satisfied = rows.filter { $0.status < 500 && $0.latency <= threshold }.count
        tolerating = rows.filter { $0.status < 500 && $0.latency > threshold && $0.latency <= threshold * 4 }.count
    }
}

final class Analyzer {
    private var records: [LogRecord] = []
    private var malformed: [(line: Int, reason: String)] = []
    private let lineCount: Int
    private var conditions: [String: String] = [:]
    private var range: (start: Int, end: Int, startText: String, endText: String)?
    private var output: [String] = []

    init(_ lines: [String]) {
        lineCount = lines.count
        for (i, line) in lines.enumerated() {
            let fields = words(line)
            if let reason = malformedReason(fields) { malformed.append((i + 1, reason)) }
            else { records.append(LogRecord(line: i + 1, fields: fields)) }
        }
        records.sort { ($0.seconds, $0.line) < ($1.seconds, $1.line) }
    }

    private func emit(_ parts: Any...) {
        output.append(parts.map { String(describing: $0) }.joined(separator: " "))
    }

    private func selected() -> [LogRecord] {
        records.filter { row in
            if let range, row.seconds < range.start || row.seconds > range.end { return false }
            if let value = conditions["METHOD"], row.method != value { return false }
            if let value = conditions["STATUS"], !statusMatches(value, row.status) { return false }
            if let value = conditions["IP"], row.ip != value { return false }
            return conditions["PATH"] == nil || row.path == conditions["PATH"]!
        }
    }

    private func barLine(_ label: String, _ count: Int, _ maximum: Int) {
        if count == 0 { emit(label, count) }
        else { emit(label, count, String(repeating: "#", count: (count * 30 + maximum - 1) / maximum)) }
    }

    func execute(_ line: String) -> [String] {
        output = []
        let tokens = words(line), name = words(line).first ?? ""
        let args = Array(tokens.dropFirst())
        do {
            try require(forms[name] != nil, "unknown query")
            let form = forms[name]!
            let optional = (name == "LATENCY" || name == "SESSIONS") && args.count == form.count - 1
            try require(args.count == form.count || optional, "wrong arguments")
            for i in args.indices {
                try require(validArgument(form[i], args[i], args), argumentErrors[form[i]]!)
            }
            let rows = selected()
            if requireRecords.contains(name) && rows.isEmpty { emit(name, "no records") }
            else { try run(name, args, rows) }
        } catch let error as QueryError {
            output = ["ERROR " + error.message]
        } catch {
            fatalError("Unexpected failure: \(error)")
        }
        return output
    }

    private func run(_ name: String, _ a: [String], _ rows: [LogRecord]) throws {
        switch name {
        case "SUMMARY":
            emit("SUMMARY", "lines", lineCount, "valid", records.count, "malformed", malformed.count)
            emit("requests", rows.count, "bytes", sum(rows, \.bytes),
                 "ips", Set(rows.map(\.ip)).count, "paths", Set(rows.map(\.path)).count)
            if let first = rows.first, let last = rows.last {
                emit("span", first.timestamp, last.timestamp, last.seconds - first.seconds)
            } else { emit("span", "none") }
        case "MALFORMED":
            emit("MALFORMED", malformed.count)
            for reason in reasons {
                let numbers = malformed.filter { $0.reason == reason }.map { String($0.line) }
                if !numbers.isEmpty { emit(reason, numbers.count, numbers.joined(separator: " ")) }
            }
        case "STATUS":
            emit("STATUS", rows.count)
            let classes = classCounts(rows), counts = frequencies(rows.map(\.status))
            for i in classes.indices { emit(statusClasses[i], classes[i], percent(classes[i], rows.count)) }
            for status in counts.keys.sorted() { emit(status, counts[status]!, percent(counts[status]!, rows.count)) }
        case "METHODS":
            emit("METHODS", rows.count)
            let counts = frequencies(rows.map(\.method))
            for method in ranked(counts) { emit(method, counts[method]!, percent(counts[method]!, rows.count)) }
        case "TOP":
            let kind = a[0]
            let counts = frequencies(rows.map { kind == "PATHS" ? $0.path : $0.ip })
            let keys = ranked(counts, ip: kind == "IPS"), shown = min(Int(a[1])!, counts.count)
            emit("TOP", kind, shown, "of", keys.count)
            var rank = 0
            for i in 0..<shown {
                if i == 0 || counts[keys[i]] != counts[keys[i - 1]] { rank = i + 1 }
                emit(rank, keys[i], counts[keys[i]]!, percent(counts[keys[i]]!, rows.count))
            }
        case "HOURLY":
            var counts = Array(repeating: 0, count: 24)
            for row in rows { counts[row.hour] += 1 }
            let maximum = counts.max()!
            emit("HOURLY", rows.count, "peak", String(format: "%02d", counts.firstIndex(of: maximum)!), maximum)
            for i in counts.indices { barLine(String(format: "%02d", i), counts[i], maximum) }
        case "TIMELINE":
            let minutes = Int(a[0])!, width = Int(a[0])! * 60
            let b = try buckets(rows.map { $0.seconds / width })
            emit("TIMELINE", minutes, b.counts.count)
            for i in b.counts.indices { barLine(intervalLabel((b.first + i) * width), b.counts[i], b.counts.max()!) }
        case "BANDWIDTH":
            let days = Dictionary(grouping: rows, by: \.date), total = sum(rows, \.bytes)
            emit("BANDWIDTH", days.count, total, bytesText(total))
            for date in days.keys.sorted() {
                let group = days[date]!, total = sum(days[date]!, \.bytes)
                emit(date, group.count, total, bytesText(total))
            }
        case "VISITORS":
            var firstDates: [String: String] = [:]
            for row in rows where firstDates[row.ip] == nil { firstDates[row.ip] = row.date }
            let days = Dictionary(grouping: rows, by: \.date)
            emit("VISITORS", days.count, firstDates.count)
            for date in days.keys.sorted() {
                let ips = Set(days[date]!.map(\.ip)), fresh = Set(days[date]!.map(\.ip)).filter { firstDates[$0] == date }.count
                emit(date, "unique", ips.count, "new", fresh, "returning", ips.count - fresh)
            }
        case "LATENCY":
            let label = a.isEmpty ? "all" : normalizePath(a[0])
            let chosen = a.isEmpty ? rows : rows.filter { $0.path == label }
            guard !chosen.isEmpty else { emit("LATENCY", "no records"); return }
            let values = chosen.map(\.latency).sorted(), count = chosen.count, trim = chosen.count / 10
            let trimmed = values[trim..<(count - trim)]
            emit("LATENCY", label, "count", count, "min", values.first!, "p50", percentile(values, 50),
                 "p90", percentile(values, 90), "p99", percentile(values, 99), "max", values.last!,
                 "mean", decimal(values.reduce(0, +), count, 2),
                 "trimmed", decimal(trimmed.reduce(0, +), trimmed.count, 2))
        case "HISTOGRAM":
            let width = Int(a[0])!, b = try buckets(rows.map { $0.latency / Int(a[0])! })
            emit("HISTOGRAM", width, b.counts.count)
            for i in b.counts.indices {
                let lower = (b.first + i) * width
                barLine("\(lower)-\(lower + width - 1)", b.counts[i], b.counts.max()!)
            }
        case "APDEX":
            let threshold = Int(a[0])!, overall = Apdex(rows, Int(a[0])!)
            emit("APDEX", threshold, overall.text, overall.rating, "satisfied", overall.satisfied,
                 "tolerating", overall.tolerating, "frustrated", overall.frustrated)
            let paths = Dictionary(grouping: rows, by: \.path).map { (path: $0.key, score: Apdex($0.value, threshold)) }
                .sorted { x, y in
                    let left = x.score.points * y.score.total, right = y.score.points * x.score.total
                    if left != right { return left < right }
                    if x.score.count != y.score.count { return x.score.count > y.score.count }
                    return x.path < y.path
                }
            for row in paths { emit(row.path, row.score.text, row.score.rating, row.score.count) }
        case "ERRORS":
            let failed = rows.filter { $0.status >= 400 }.count
            emit("ERRORS", failed, "of", rows.count, percent(failed, rows.count))
            let paths = Dictionary(grouping: rows, by: \.path).map { entry in
                (path: entry.key, count: entry.value.count,
                 client: entry.value.filter { $0.status / 100 == 4 }.count,
                 server: entry.value.filter { $0.status / 100 == 5 }.count)
            }.filter { $0.client + $0.server > 0 }.sorted { x, y in
                let xf = x.client + x.server, yf = y.client + y.server
                if xf * y.count != yf * x.count { return xf * y.count > yf * x.count }
                if xf != yf { return xf > yf }
                return x.path < y.path
            }
            for row in paths { emit(row.path, row.count, row.client, row.server, percent(row.client + row.server, row.count)) }
        case "SLOWEST":
            let paths = Dictionary(grouping: rows, by: { $0.method + "\u{1}" + $0.path }).values.map { group in
                (method: group[0].method, path: group[0].path, count: group.count,
                 total: sum(group, \.latency), maximum: group.map(\.latency).max()!)
            }.sorted { x, y in
                if x.total * y.count != y.total * x.count { return x.total * y.count > y.total * x.count }
                if x.maximum != y.maximum { return x.maximum > y.maximum }
                return (x.path, x.method) < (y.path, y.method)
            }
            let shown = min(Int(a[0])!, paths.count)
            emit("SLOWEST", shown, "of", paths.count)
            for (i, row) in paths.prefix(shown).enumerated() {
                emit(i + 1, row.method, row.path, "count", row.count, "avg", decimal(row.total, row.count, 2), "max", row.maximum)
            }
        case "SESSIONS":
            let ip = a[0], minutes = a.count == 2 ? Int(a[1])! : 30
            let found = rows.filter { $0.ip == ip }
            guard !found.isEmpty else { emit("SESSIONS", "no records"); return }
            var sessions = [[found[0]]]
            for i in 1..<found.count {
                if found[i].seconds - found[i - 1].seconds <= minutes * 60 { sessions[sessions.count - 1].append(found[i]) }
                else { sessions.append([found[i]]) }
            }
            let duration = sessions.reduce(0) { $0 + $1.last!.seconds - $1.first!.seconds }
            emit("SESSIONS", ip, "timeout", minutes, "count", sessions.count, "requests", found.count,
                 "avg_duration", decimal(duration, sessions.count, 1), "avg_requests", decimal(found.count, sessions.count, 1))
            for (i, session) in sessions.enumerated() {
                emit(i + 1, session.first!.timestamp, session.last!.timestamp,
                     session.last!.seconds - session.first!.seconds, session.count, Set(session.map(\.path)).count)
            }
        case "BURST":
            let width = Int(a[0])!, threshold = Int(a[1])!
            let groups = Dictionary(grouping: rows.filter { $0.status >= 400 }, by: \.ip)
            let peaks = groups.map { (ip: $0.key, window: peak($0.value, width)) }.filter { $0.window.count >= threshold }
                .sorted { x, y in
                    if x.window.count != y.window.count { return x.window.count > y.window.count }
                    return ipNumber(x.ip) < ipNumber(y.ip)
                }
            emit("BURST", width, threshold, peaks.count)
            for row in peaks { emit(row.ip, row.window.count, row.window.first.timestamp, row.window.last.timestamp) }
        case "PEAK":
            let width = Int(a[0])!, window = peak(rows, Int(a[0])!)
            emit("PEAK", width, window.count, window.first.timestamp, window.last.timestamp)
        case "GAPS":
            let width = Int(a[0])!
            let gaps = rows.indices.dropFirst().filter { rows[$0].seconds - rows[$0 - 1].seconds >= width }
            emit("GAPS", width, gaps.count)
            for i in gaps { emit(rows[i - 1].timestamp, rows[i].timestamp, rows[i].seconds - rows[i - 1].seconds) }
        case "IP":
            let found = rows.filter { $0.ip == a[0] }
            guard !found.isEmpty else { emit("IP", "no records"); return }
            let paths = frequencies(found.map(\.path)), methods = frequencies(found.map(\.method))
            emit("IP", a[0], "requests", found.count, "bytes", sum(found, \.bytes),
                 "errors", found.filter { $0.status >= 400 }.count, "paths", paths.count)
            emit("first", found.first!.timestamp, "last", found.last!.timestamp)
            emit("methods", ranked(methods).map { "\($0) \(methods[$0]!)" }.joined(separator: " "))
            let counts = classCounts(found)
            emit("classes", counts.indices.map { "\(statusClasses[$0]) \(counts[$0])" }.joined(separator: " "))
            for path in ranked(paths).prefix(3) { emit("path", path, paths[path]!) }
        case "RANGE":
            let start = secondsOf(a[0], a[1]), end = secondsOf(a[2], a[3])
            try require(start <= end, "invalid range")
            range = (start, end, a[0] + " " + a[1], a[2] + " " + a[3])
            emit("RANGE", range!.startText, range!.endText, "active", selected().count)
        case "FILTER":
            let key = a[0], value = a[0] == "PATH" ? normalizePath(a[1]) : a[1]
            conditions[key] = value
            emit("FILTER", key, value, "active", selected().count)
        case "UNFILTER":
            let key = a[0]
            if key == "RANGE" {
                try require(range != nil, "not filtered")
                range = nil
            } else {
                try require(conditions[key] != nil, "not filtered")
                conditions.removeValue(forKey: key)
            }
            emit("UNFILTER", key, "active", selected().count)
        case "RESET":
            range = nil
            conditions.removeAll()
            emit("RESET", "active", selected().count)
        case "STATE":
            let rangeText = range.map { $0.startText + " " + $0.endText } ?? "-"
            let filters = filterKeys.map { $0.lowercased() + " " + (conditions[$0] ?? "-") }.joined(separator: " ")
            emit("STATE", "active", rows.count, "range", rangeText, filters)
        default:
            preconditionFailure("Unknown query passed validation")
        }
    }
}

var logs: [String] = []
while let line = readLine() {
    if line == "---" { break }
    logs.append(line)
}
let analyzer = Analyzer(logs)
while let line = readLine() {
    if line == "END" { break }
    for result in analyzer.execute(line) { print(result) }
}

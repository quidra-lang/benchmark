import Foundation

enum ColumnType: Int, CaseIterable {
    case int, string, bool, date
    var name: String { ["INT", "STRING", "BOOL", "DATE"][rawValue] }
    init(name: String) { self = Self.allCases.first { $0.name == name }! }
}

enum Value: Hashable, Comparable {
    case integer(Int)
    case string(String)
    case boolean(Bool)
    case null
    case unknown

    var intValue: Int { if case .integer(let value) = self { return value }; preconditionFailure("Integer required") }
    var stringValue: String { if case .string(let value) = self { return value }; preconditionFailure("String required") }
    var boolValue: Bool { if case .boolean(let value) = self { return value }; preconditionFailure("Boolean required") }
    static func < (a: Value, b: Value) -> Bool {
        if a == .null { return b != .null }
        if b == .null { return false }
        switch (a, b) {
        case (.integer(let x), .integer(let y)): return x < y
        case (.string(let x), .string(let y)): return x < y
        case (.boolean(let x), .boolean(let y)): return !x && y
        default: preconditionFailure("Incomparable values")
        }
    }
}

struct Column {
    let name: String
    let type: ColumnType
    let nullable: Bool
}

func leap(_ year: Int) -> Bool { year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) }
func monthLengths(_ year: Int) -> [Int] { [31, leap(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] }
func dayNumber(_ text: String) -> Int {
    let parts = text.split(separator: "-").map { Int($0)! }, year = Int(text.prefix(4))!
    func before(_ year: Int) -> Int { let y = year - 1; return 365 * y + y / 4 - y / 100 + y / 400 }
    return before(year) - before(1970) + monthLengths(year).prefix(parts[1] - 1).reduce(0, +) + parts[2] - 1
}
func dateText(_ day: Int) -> String {
    var year = 1970, remaining = day
    while remaining < 0 { year -= 1; remaining += leap(year) ? 366 : 365 }
    while remaining >= (leap(year) ? 366 : 365) { remaining -= leap(year) ? 366 : 365; year += 1 }
    var month = 1
    for length in monthLengths(year) { if remaining < length { break }; remaining -= length; month += 1 }
    return String(format: "%04d-%02d-%02d", year, month, remaining + 1)
}
func parseValue(_ type: ColumnType, _ text: String) -> Value {
    if text.isEmpty { return .null }
    switch type {
    case .int: return .integer(Int(text)!)
    case .date: return .integer(dayNumber(text))
    case .bool: return .boolean(text == "true")
    case .string: return .string(text)
    }
}
func valueText(_ type: ColumnType, _ value: Value, null: String = "NULL") -> String {
    if value == .null { return null }
    if value == .unknown { return "?" }
    switch type {
    case .int: return String(value.intValue)
    case .date: return dateText(value.intValue)
    case .bool: return value.boolValue ? "true" : "false"
    case .string: return value.stringValue
    }
}
func readLines(_ path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .ascii).split(separator: "\n").map(String.init)
}
struct Inputs {
    var columns: [Column] = []
    var rows: [[Value]] = []
    var rowGroupSize = 0, pageSize = 0, dictionaryLimit = 0
    var methods: [String: String] = [:]
    let queries: [String]
    let damaged: [UInt8]
    init() throws {
        for line in try readLines("input/schema.txt") {
            let f = line.split(separator: " ").map(String.init)
            columns.append(Column(name: f[0], type: ColumnType(name: f[1]), nullable: f[2] == "NULLABLE"))
        }
        for line in try readLines("input/table.csv").dropFirst() {
            rows.append(zip(columns, line.components(separatedBy: ",")).map { parseValue($0.0.type, $0.1) })
        }
        for line in try readLines("input/options.txt") {
            let f = line.split(separator: " ").map(String.init)
            switch f[0] {
            case "row_group_size": rowGroupSize = Int(f[1])!
            case "page_size": pageSize = Int(f[1])!
            case "dictionary_limit": dictionaryLimit = Int(f[1])!
            default: methods[f[1]] = f[2]
            }
        }
        queries = try readLines("input/queries.txt")
        let hex = Array(try readLines("input/damaged.hex").joined())
        damaged = stride(from: 0, to: hex.count, by: 2).map { UInt8(String(hex[$0..<($0 + 2)]), radix: 16)! }
    }
}
func writeOutputs(_ outputs: [String: [String]]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    for name in outputs.keys.sorted() {
        try outputs[name]!.map { $0 + "\n" }.joined().write(toFile: "output/" + name, atomically: true, encoding: .ascii)
    }
}

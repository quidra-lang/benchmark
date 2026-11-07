import Foundation

let scanCountNames = ["row_groups_read", "row_groups_skipped", "pages_read", "pages_skipped", "pages_unneeded",
                      "dictionary_pages_read", "bytes_read", "rows_scanned", "rows_matched"]
func statistics(_ values: [Value]) -> Bounds? {
    let present = values.filter { $0 != .null }
    guard let low = present.min(), let high = present.max() else { return nil }
    return Bounds(low: low, high: high)
}
func statisticsText(_ column: Column, _ bounds: Bounds?) -> String {
    bounds.map { "min \(valueText(column.type, $0.low)) max \(valueText(column.type, $0.high))" } ?? "stats none"
}
func methodList(_ methods: [Method]) -> String { methods.map(\.name).joined(separator: ",") }
func columnLine(_ index: Int, _ column: Column) -> String { "column \(index) \(column.name) \(column.type.name) \(column.nullable ? "NULLABLE" : "REQUIRED")" }
func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", Int($0)) }.joined() }
func checksumText(_ value: Int) -> String { String(format: "%08x", value) }

func buildPage(_ column: Column, dictionaryPage: Bool, method: Method, values: [Value], dictionary: [Value] = []) -> [UInt8] {
    let body: [UInt8], nulls: Int, bounds: Bounds?
    if dictionaryPage { body = encodeValues(column.type, method: .plain, values: values); nulls = 0; bounds = nil }
    else {
        let present = values.filter { $0 != .null }
        nulls = values.count - present.count; bounds = statistics(values)
        let definitions = column.nullable ? hybridEncode(values.map { $0 == .null ? 0 : 1 }, width: 1) : []
        body = (column.nullable ? littleEndian(definitions.count) + definitions : [])
            + encodeValues(column.type, method: method, values: present, dictionary: dictionary)
    }
    return [dictionaryPage ? 1 : 0, UInt8(method.rawValue)] + uleb(values.count) + uleb(nulls) + uleb(body.count)
        + littleEndian(adler32(body)) + encodeStatistics(column.type, bounds) + body
}

struct BuiltChunk {
    let data: [UInt8]
    let methods: [Method]
    let hasDictionary: Bool
    let pageCount: Int
    let nulls: Int
    let bounds: Bounds?
    let fallback: Int
}
func buildChunk(_ column: Column, values: [Value], method: Method, pageSize: Int, dictionaryLimit: Int) -> BuiltChunk {
    let pages = stride(from: 0, to: values.count, by: pageSize).map { Array(values[$0..<min($0 + pageSize, values.count)]) }
    var dictionary: [Value] = [], dictionaryPages = 0
    if method == .dictionary {
        var known: Set<Value> = [], dictionaryBytes = 0
        for page in pages {
            var additions: [Value] = [], proposed = known
            for value in page where value != .null && proposed.insert(value).inserted { additions.append(value) }
            let size = dictionaryBytes + encodeValues(column.type, method: .plain, values: additions).count
            if size > dictionaryLimit { break }
            dictionary += additions; known = proposed; dictionaryBytes = size; dictionaryPages += 1
        }
        if dictionary.isEmpty { dictionaryPages = 0 }
    }
    var data = dictionaryPages > 0 ? buildPage(column, dictionaryPage: true, method: .plain, values: dictionary) : []
    var methods: Set<Method> = []
    for (number, page) in pages.enumerated() {
        let selected: Method = method == .dictionary ? (number < dictionaryPages ? .dictionary : .plain) : method
        methods.insert(selected)
        data += buildPage(column, dictionaryPage: false, method: selected, values: page, dictionary: dictionary)
    }
    return BuiltChunk(data: data, methods: methods.sorted { $0.rawValue < $1.rawValue }, hasDictionary: dictionaryPages > 0,
        pageCount: pages.count, nulls: values.filter { $0 == .null }.count, bounds: statistics(values),
        fallback: method == .dictionary ? pages.count - dictionaryPages : 0)
}

func buildFile(_ input: Inputs) -> ([UInt8], [String]) {
    var data = Array("MPTC".utf8), groups: [(Int, [(Int, BuiltChunk)])] = []
    var report = ["row_group,column,encoding,bytes,fallback_pages,chosen"]
    for first in stride(from: 0, to: input.rows.count, by: input.rowGroupSize) {
        let rows = Array(input.rows[first..<min(first + input.rowGroupSize, input.rows.count)])
        var chunks: [(Int, BuiltChunk)] = []
        for (index, column) in input.columns.enumerated() {
            let values = rows.map { $0[index] }, methods = candidates(column.type)
            let choices = methods.map { buildChunk(column, values: values, method: $0, pageSize: input.pageSize, dictionaryLimit: input.dictionaryLimit) }
            let requested = input.methods[column.name]!
            var chosen: Int
            if requested == "AUTO" {
                chosen = 0
                for candidate in choices.indices.dropFirst() where choices[candidate].data.count < choices[chosen].data.count { chosen = candidate }
            } else {
                chosen = methods.firstIndex(of: Method(name: requested))!
                if methods[chosen] == .dictionary && !choices[chosen].hasDictionary { chosen = methods.firstIndex(of: .plain)! }
            }
            for (candidate, method) in methods.enumerated() {
                report.append("\(groups.count),\(column.name),\(method.name),\(choices[candidate].data.count),\(choices[candidate].fallback),\(candidate == chosen ? "yes" : "no")")
            }
            chunks.append((data.count, choices[chosen])); data += choices[chosen].data
        }
        groups.append((rows.count, chunks))
    }
    var footer = uleb(1) + uleb(input.columns.count)
    for column in input.columns {
        footer += uleb(column.name.utf8.count) + Array(column.name.utf8) + [UInt8(column.type.rawValue), column.nullable ? 1 : 0]
    }
    footer += uleb(input.rows.count) + uleb(groups.count)
    for (rows, chunks) in groups {
        footer += uleb(rows)
        for (column, entry) in zip(input.columns, chunks) {
            let (offset, chunk) = entry
            footer += uleb(offset) + uleb(chunk.data.count) + uleb(chunk.methods.count) + chunk.methods.map { UInt8($0.rawValue) }
            footer += [chunk.hasDictionary ? 1 : 0] + uleb(chunk.pageCount) + uleb(chunk.nulls) + encodeStatistics(column.type, chunk.bounds)
        }
    }
    return (data + footer + littleEndian(footer.count) + Array("MPTC".utf8), report)
}

struct Page {
    let offset: Int, kind: Int
    let method: Method
    let count: Int, nulls: Int, bodySize: Int, checksum: Int
    let bounds: Bounds?
    let headerSize: Int, bodyOffset: Int
    var size: Int { headerSize + bodySize }
}
final class Chunk {
    let offset: Int, size: Int
    let methods: [Method]
    let hasDictionary: Bool
    let pageCount: Int, nulls: Int
    let bounds: Bounds?
    var dictionary: Page?
    var pages: [Page] = []
    init(_ reader: Reader, column: Column) {
        offset = reader.uleb(); size = reader.uleb()
        methods = (0..<reader.uleb()).map { _ in Method(rawValue: reader.byte())! }
        hasDictionary = reader.byte() != 0; pageCount = reader.uleb(); nulls = reader.uleb()
        bounds = decodeStatistics(reader, type: column.type)
    }
}
struct RowGroup {
    let rows: Int, firstRow: Int
    let chunks: [Chunk]
}
struct ColumnarFile {
    let data: [UInt8]
    let version: Int
    let columns: [Column]
    let rows: Int
    let groups: [RowGroup]
    let footerSize: Int, footerOffset: Int
    init(_ data: [UInt8]) {
        self.data = data
        footerSize = Reader(data, position: data.count - 8).integer()
        footerOffset = data.count - 8 - footerSize
        let reader = Reader(data, position: footerOffset)
        version = reader.uleb()
        var columns: [Column] = []
        for _ in 0..<reader.uleb() {
            let name = String(bytes: reader.read(reader.uleb()), encoding: .ascii)!, type = ColumnType(rawValue: reader.byte())!
            columns.append(Column(name: name, type: type, nullable: reader.byte() != 0))
        }
        self.columns = columns
        rows = reader.uleb()
        var groups: [RowGroup] = [], first = 0
        for _ in 0..<reader.uleb() {
            let count = reader.uleb(), chunks = columns.map { Chunk(reader, column: $0) }
            groups.append(RowGroup(rows: count, firstRow: first, chunks: chunks)); first += count
        }
        for group in groups {
            for (column, chunk) in zip(columns, group.chunks) {
                let reader = Reader(data, position: chunk.offset)
                var pages: [Page] = []
                while reader.position < chunk.offset + chunk.size {
                    let offset = reader.position, kind = reader.byte(), method = Method(rawValue: reader.byte())!
                    let count = reader.uleb(), nulls = reader.uleb(), bodySize = reader.uleb(), checksum = reader.integer()
                    let bounds = decodeStatistics(reader, type: column.type), bodyOffset = reader.position
                    pages.append(Page(offset: offset, kind: kind, method: method, count: count, nulls: nulls, bodySize: bodySize,
                        checksum: checksum, bounds: bounds, headerSize: bodyOffset - offset, bodyOffset: bodyOffset))
                    reader.position += bodySize
                }
                if chunk.hasDictionary { chunk.dictionary = pages.removeFirst() }
                chunk.pages = pages
            }
        }
        self.groups = groups
    }
    func body(_ page: Page) -> [UInt8] { Array(data[page.bodyOffset..<(page.bodyOffset + page.bodySize)]) }
    func decodeDictionary(_ column: Column, _ page: Page) -> [Value] {
        decodeValues(Reader(body(page)), type: column.type, method: .plain, count: page.count)
    }
    func decodePage(_ column: Column, _ page: Page, dictionary: [Value] = []) -> [Value] {
        let reader = Reader(body(page))
        let definitions = column.nullable ? hybridDecode(Reader(reader.read(reader.integer())), width: 1, count: page.count)
            : Array(repeating: 1, count: page.count)
        let values = decodeValues(reader, type: column.type, method: page.method, count: definitions.filter { $0 == 1 }.count, dictionary: dictionary)
        var index = 0
        return definitions.map { definition in
            if definition == 0 { return .null }
            defer { index += 1 }; return values[index]
        }
    }
}

func verifyAndDescribe(_ file: ColumnarFile, original: [[Value]]) -> [String] {
    var lines = ["file bytes \(file.data.count) footer_offset \(file.footerOffset) footer_bytes \(file.footerSize)",
        "table version \(file.version) rows \(file.rows) columns \(file.columns.count) row_groups \(file.groups.count)"]
    lines += file.columns.enumerated().map { columnLine($0.offset, $0.element) }
    var bytes = Array(repeating: 0, count: file.columns.count), pages = bytes, dictionaries = bytes
    var methods = Array(repeating: Set<Method>(), count: file.columns.count)
    var cells = 0, nulls = 0, mismatches = 0, checksumErrors = 0
    for (number, group) in file.groups.enumerated() {
        lines.append("row_group \(number) rows \(group.rows) first_row \(group.firstRow) bytes \(group.chunks.reduce(0) { $0 + $1.size })")
        for (index, column) in file.columns.enumerated() {
            let chunk = group.chunks[index]
            lines.append("chunk \(number) \(column.name) offset \(chunk.offset) size \(chunk.size) encodings \(methodList(chunk.methods)) "
                + "dictionary \(chunk.hasDictionary ? "yes" : "no") pages \(chunk.pageCount) nulls \(chunk.nulls) \(statisticsText(column, chunk.bounds))")
            bytes[index] += chunk.size; pages[index] += chunk.pageCount; dictionaries[index] += chunk.hasDictionary ? 1 : 0
            methods[index].formUnion(chunk.methods)
            var dictionary: [Value] = []
            if let page = chunk.dictionary {
                if adler32(file.body(page)) != page.checksum { checksumErrors += 1 }
                dictionary = file.decodeDictionary(column, page)
                lines.append("page \(number) \(column.name) dict offset \(page.offset) header \(page.headerSize) body \(page.bodySize) checksum \(checksumText(page.checksum)) entries \(page.count)")
            }
            var row = group.firstRow
            for (p, page) in chunk.pages.enumerated() {
                if adler32(file.body(page)) != page.checksum { checksumErrors += 1 }
                lines.append("page \(number) \(column.name) \(p) offset \(page.offset) header \(page.headerSize) body \(page.bodySize) "
                    + "checksum \(checksumText(page.checksum)) encoding \(page.method.name) values \(page.count) nulls \(page.nulls) \(statisticsText(column, page.bounds))")
                for value in file.decodePage(column, page, dictionary: dictionary) {
                    cells += 1; if value == .null { nulls += 1 }; if value != original[row][index] { mismatches += 1 }; row += 1
                }
            }
        }
    }
    for (index, column) in file.columns.enumerated() {
        lines.append("summary \(column.name) bytes \(bytes[index]) data_pages \(pages[index]) dictionary_pages \(dictionaries[index]) encodings "
            + methodList(methods[index].sorted { $0.rawValue < $1.rawValue }))
    }
    lines.append("roundtrip \(mismatches == 0 && checksumErrors == 0 ? "ok" : "failed") cells \(cells) nulls \(nulls) mismatches \(mismatches) checksum_errors \(checksumErrors)")
    return lines
}

func conditionLeaves(_ tree: RawCondition?) -> [Comparison] {
    guard let tree else { return [] }
    switch tree { case .comparison(let clause): return [clause]; case .not(let child): return conditionLeaves(child)
    case .pair(_, let left, let right): return conditionLeaves(left) + conditionLeaves(right) }
}
indirect enum Condition {
    case comparison(String, Int, [Value])
    case not(Condition)
    case pair(String, Condition, Condition)
}
struct PlanItem {
    let operation: String
    let index: Int?
}
struct Plan {
    let items: [PlanItem]
    let headers: [String]
    let condition: Condition?
    let group: Int?
    let order: Int?
    let descending: Bool
    let limit: Int?
    let aggregate: Bool
    let needed: [Int]
    let conditionColumns: [Int]
}
func checkQuery(_ raw: RawQuery, columns: [Column]) -> (String?, Plan?) {
    let indices = Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($0.element.name, $0.offset) })
    let items = raw.items ?? columns.map { SelectItem(operation: "COLUMN", name: $0.name) }
    let leaves = conditionLeaves(raw.condition)
    let names = items.compactMap(\.name) + leaves.map(\.name) + [raw.group, raw.order].compactMap { $0 }
    if names.contains(where: { indices[$0] == nil }) { return ("unknown_column", nil) }
    for leaf in leaves {
        let type = columns[indices[leaf.name]!].type, expected: ColumnType = type == .date ? .string : type
        if leaf.literals.contains(where: { $0.type != expected }) { return ("type_mismatch", nil) }
    }
    if items.contains(where: { ["SUM", "AVG"].contains($0.operation) && columns[indices[$0.name!]!].type != .int }) { return ("bad_aggregate", nil) }
    let aggregate = raw.group != nil || items.contains { $0.operation != "COLUMN" }
    if aggregate && items.contains(where: { $0.operation == "COLUMN" && $0.name != raw.group }) { return ("not_grouped", nil) }
    if aggregate && raw.order != nil { return ("bad_order", nil) }
    func convert(_ tree: RawCondition?) -> Condition? {
        guard let tree else { return nil }
        switch tree {
        case .not(let child): return .not(convert(child)!)
        case .pair(let operation, let left, let right): return .pair(operation, convert(left)!, convert(right)!)
        case .comparison(let clause):
            let index = indices[clause.name]!
            let values = clause.literals.map { columns[index].type == .date ? Value.integer(dayNumber($0.value.stringValue)) : $0.value }
            return .comparison(clause.operation, index, values)
        }
    }
    let headers = items.map { item -> String in
        if item.operation == "COLUMN" { return item.name! }
        if item.operation == "COUNT_DISTINCT" { return "COUNT(DISTINCT \(item.name!))" }
        return "\(item.operation)(\(item.name ?? "*"))"
    }
    let plan = Plan(items: items.map { PlanItem(operation: $0.operation, index: $0.name.map { indices[$0]! }) },
        headers: headers, condition: convert(raw.condition), group: raw.group.map { indices[$0]! }, order: raw.order.map { indices[$0]! },
        descending: raw.descending, limit: raw.limit, aggregate: aggregate, needed: Set(names.map { indices[$0]! }).sorted(),
        conditionColumns: Set(leaves.map { indices[$0.name]! }).sorted())
    return (nil, plan)
}

enum Truth: Hashable {
    case yes, no, unknown
}
func logicalNot(_ value: Truth) -> Truth { value == .yes ? .no : value == .no ? .yes : .unknown }
func logicalPair(_ operation: String, _ left: Truth, _ right: Truth) -> Truth {
    if operation == "AND" { return left == .no || right == .no ? .no : left == .unknown || right == .unknown ? .unknown : .yes }
    return left == .yes || right == .yes ? .yes : left == .unknown || right == .unknown ? .unknown : .no
}
func compareValue(_ operation: String, _ value: Value, _ literals: [Value]) -> Truth {
    if operation == "IS_NULL" { return value == .null ? .yes : .no }
    if operation == "IS_NOT_NULL" { return value == .null ? .no : .yes }
    if value == .null { return .unknown }
    let result: Bool
    switch operation {
    case "BETWEEN": result = literals[0] <= value && value <= literals[1]
    case "IN": result = literals.contains(value)
    case "=": result = value == literals[0]
    case "<>": result = value != literals[0]
    case "<": result = value < literals[0]
    case "<=": result = value <= literals[0]
    case ">": result = value > literals[0]
    default: result = value >= literals[0]
    }
    return result ? .yes : .no
}
func evaluate(_ tree: Condition?, row: [Value]) -> Truth {
    guard let tree else { return .yes }
    switch tree {
    case .not(let child): return logicalNot(evaluate(child, row: row))
    case .pair(let operation, let left, let right): return logicalPair(operation, evaluate(left, row: row), evaluate(right, row: row))
    case .comparison(let operation, let index, let literals): return compareValue(operation, row[index], literals)
    }
}
func rangePossibilities(_ operation: String, bounds: Bounds, literals: [Value]) -> (Bool, Bool) {
    let low = bounds.low, high = bounds.high
    switch operation {
    case "BETWEEN": return (low <= literals[1] && high >= literals[0] && literals[0] <= literals[1], low < literals[0] || high > literals[1])
    case "IN": return (literals.contains { low <= $0 && $0 <= high }, !(low == high && literals.contains(low)))
    case "=": return (low <= literals[0] && literals[0] <= high, !(low == literals[0] && high == literals[0]))
    case "<>": return (!(low == literals[0] && high == literals[0]), low <= literals[0] && literals[0] <= high)
    case "<": return (low < literals[0], high >= literals[0])
    case "<=": return (low <= literals[0], high > literals[0])
    case ">": return (high > literals[0], low <= literals[0])
    default: return (high >= literals[0], low < literals[0])
    }
}
struct Zone {
    let bounds: Bounds?
    let nulls: Int
    let rows: Int
}
func zoneValues(_ tree: Condition, zones: [Int: Zone]) -> Set<Truth> {
    switch tree {
    case .not(let child): return Set(zoneValues(child, zones: zones).map(logicalNot))
    case .pair(let operation, let left, let right):
        let first = zoneValues(left, zones: zones), second = zoneValues(right, zones: zones)
        return Set(first.flatMap { a in second.map { logicalPair(operation, a, $0) } })
    case .comparison(let operation, let index, let literals):
        let zone = zones[index]!
        var values: Set<Truth> = []
        if operation == "IS_NULL" || operation == "IS_NOT_NULL" {
            if zone.nulls > 0 { values.insert(operation == "IS_NULL" ? .yes : .no) }
            if zone.nulls < zone.rows { values.insert(operation == "IS_NOT_NULL" ? .yes : .no) }
        } else {
            if zone.nulls > 0 { values.insert(.unknown) }
            if let bounds = zone.bounds {
                let (canBeTrue, canBeFalse) = rangePossibilities(operation, bounds: bounds, literals: literals)
                if canBeTrue { values.insert(.yes) }; if canBeFalse { values.insert(.no) }
            }
        }
        return values
    }
}

final class ScanCounts {
    var values: [String: Int] = [:]
    subscript(_ key: String) -> Int {
        get { values[key, default: 0] }
        set { values[key] = newValue }
    }
    var text: String { scanCountNames.map { "\($0) \(self[$0])" }.joined(separator: " ") }
}
struct DictionaryKey: Hashable {
    let group: Int
    let column: Int
}
func readScanPage(_ file: ColumnarFile, group: Int, index: Int, pageNumber: Int,
                  dictionaries: inout [DictionaryKey: [Value]], counts: ScanCounts) -> [Value] {
    let column = file.columns[index], chunk = file.groups[group].chunks[index], page = file.groups[group].chunks[index].pages[pageNumber]
    var dictionary: [Value] = []
    if page.method == .dictionary {
        let key = DictionaryKey(group: group, column: index)
        if dictionaries[key] == nil {
            dictionaries[key] = file.decodeDictionary(column, chunk.dictionary!)
            counts["dictionary_pages_read"] += 1; counts["bytes_read"] += chunk.dictionary!.size
        }
        dictionary = dictionaries[key]!
    }
    counts["pages_read"] += 1; counts["bytes_read"] += page.size
    return file.decodePage(column, page, dictionary: dictionary)
}
func scan(_ file: ColumnarFile, plan: Plan) -> ([[Value]], ScanCounts, [String?]) {
    let counts = ScanCounts(), conditionColumns = plan.conditionColumns
    let remaining = plan.needed.filter { !conditionColumns.contains($0) }
    var records: [String?] = [], matched: [[Value]] = [], dictionaries: [DictionaryKey: [Value]] = [:]
    for (number, group) in file.groups.enumerated() {
        let zones = Dictionary(uniqueKeysWithValues: conditionColumns.map { ($0, Zone(bounds: group.chunks[$0].bounds, nulls: group.chunks[$0].nulls, rows: group.rows)) })
        if let condition = plan.condition, !zoneValues(condition, zones: zones).contains(.yes) {
            counts["row_groups_skipped"] += 1; records.append(nil); continue
        }
        counts["row_groups_read"] += 1
        if plan.needed.isEmpty {
            counts["rows_scanned"] += group.rows
            matched += Array(repeating: Array(repeating: .null, count: file.columns.count), count: group.rows)
            records.append("-"); continue
        }
        var record = ""
        for pageNumber in 0..<group.chunks[0].pageCount {
            let zones = Dictionary(uniqueKeysWithValues: conditionColumns.map { index in
                let page = group.chunks[index].pages[pageNumber]
                return (index, Zone(bounds: page.bounds, nulls: page.nulls, rows: page.count))
            })
            if let condition = plan.condition, !zoneValues(condition, zones: zones).contains(.yes) {
                counts["pages_skipped"] += plan.needed.count; record += "s"; continue
            }
            let rowCount = group.chunks[0].pages[pageNumber].count
            counts["rows_scanned"] += rowCount
            var rows = Array(repeating: Array(repeating: Value.null, count: file.columns.count), count: rowCount)
            for index in conditionColumns {
                let values = readScanPage(file, group: number, index: index, pageNumber: pageNumber, dictionaries: &dictionaries, counts: counts)
                for row in 0..<rowCount { rows[row][index] = values[row] }
            }
            let selected = rows.indices.filter { evaluate(plan.condition, row: rows[$0]) == .yes }
            if selected.isEmpty && !remaining.isEmpty { counts["pages_unneeded"] += remaining.count; record += "u"; continue }
            for index in remaining {
                let values = readScanPage(file, group: number, index: index, pageNumber: pageNumber, dictionaries: &dictionaries, counts: counts)
                for row in 0..<rowCount { rows[row][index] = values[row] }
            }
            matched += selected.map { rows[$0] }; record += "r"
        }
        records.append(record)
    }
    counts["rows_matched"] = matched.count
    return (matched, counts, records)
}

func gcd(_ first: Int, _ second: Int) -> Int {
    var a = abs(first), b = abs(second)
    while b != 0 { (a, b) = (b, a % b) }
    return a
}
func aggregateItem(_ item: PlanItem, columns: [Column], rows: [[Value]], key: Value) -> String {
    if item.operation == "COLUMN" { return valueText(columns[item.index!].type, key) }
    if item.operation == "COUNT" && item.index == nil { return String(rows.count) }
    let index = item.index!, values = rows.map { $0[item.index!] }.filter { $0 != .null }
    if item.operation == "COUNT" { return String(values.count) }
    if item.operation == "COUNT_DISTINCT" { return String(Set(values).count) }
    if values.isEmpty { return "NULL" }
    if item.operation == "SUM" { return String(values.reduce(0) { $0 + $1.intValue }) }
    if item.operation == "AVG" {
        let total = values.reduce(0) { $0 + $1.intValue }
        let divisor = gcd(total, values.count)
        let numerator = total / divisor, denominator = values.count / divisor
        return denominator == 1 ? String(numerator) : "\(numerator)/\(denominator)"
    }
    return valueText(columns[index].type, item.operation == "MIN" ? values.min()! : values.max()!)
}
struct QueryResult: Equatable {
    let kind: String
    let matched: Int
    let output: [String]
}
func buildResult(_ columns: [Column], plan: Plan, matched: [[Value]]) -> QueryResult {
    let kind: String
    var output: [String]
    if !plan.aggregate {
        kind = "rows"
        var arranged = matched
        if let index = plan.order {
            arranged = matched.enumerated().sorted {
                let left = $0.element[index], right = $1.element[index]
                if left == right { return $0.offset < $1.offset }
                return plan.descending ? left > right : left < right
            }.map(\.element)
        }
        output = arranged.map { row in plan.items.map { valueText(columns[$0.index!].type, row[$0.index!]) }.joined(separator: ",") }
    } else {
        var groups: [(Value, [[Value]])]
        if let index = plan.group {
            kind = "grouped"
            var grouped: [Value: [[Value]]] = [:]
            for row in matched { grouped[row[index], default: []].append(row) }
            groups = grouped.keys.sorted().map { ($0, grouped[$0]!) }
        } else { kind = "aggregate"; groups = [(.null, matched)] }
        output = groups.map { key, rows in plan.items.map { aggregateItem($0, columns: columns, rows: rows, key: key) }.joined(separator: ",") }
    }
    if let limit = plan.limit { output = Array(output.prefix(limit)) }
    return QueryResult(kind: kind, matched: matched.count, output: output)
}

func executeQueries(_ file: ColumnarFile, originals: [[Value]], queries: [String]) -> ([String], [String]) {
    var results: [String] = [], statistics: [String] = [], errors = 0, checksOK = 0
    let totals = ScanCounts()
    for (index, text) in queries.enumerated() {
        let number = index + 1, (error, prepared) = checkQuery(QueryParser(text).parse(), columns: file.columns)
        if let error {
            let line = "query \(number) error \(error)"
            results.append(line); statistics.append(line); errors += 1; continue
        }
        let plan = prepared!, (matched, counts, records) = scan(file, plan: prepared!)
        let result = buildResult(file.columns, plan: plan, matched: matched)
        let reference = originals.filter { evaluate(plan.condition, row: $0) == .yes }
        let check = result == buildResult(file.columns, plan: plan, matched: reference) ? "ok" : "mismatch"
        if check == "ok" { checksOK += 1 }
        results.append("query \(number) \(result.kind) matched \(result.matched) output \(result.output.count)")
        results.append("columns " + plan.headers.joined(separator: ",")); results += result.output
        let needed = plan.needed.map { file.columns[$0].name }.joined(separator: ",")
        statistics.append("query \(number) columns \(needed.isEmpty ? "-" : needed) \(counts.text) check \(check)")
        for (group, record) in records.enumerated() { statistics.append("query \(number) row_group \(group) " + (record.map { "pages " + $0 } ?? "skipped")) }
        for name in scanCountNames { totals[name] += counts[name] }
    }
    statistics.append("total queries \(queries.count) errors \(errors) \(totals.text) checks_ok \(checksOK)")
    return (results, statistics)
}

func recover(_ data: [UInt8]) -> ([String], [String]) {
    let file = ColumnarFile(data), columns = file.columns
    var rows = Array(repeating: Array(repeating: Value.unknown, count: columns.count), count: file.rows)
    var lines = ["file bytes \(data.count) rows \(file.rows) columns \(columns.count) row_groups \(file.groups.count)"]
    lines += columns.enumerated().map { columnLine($0.offset, $0.element) }
    var examined = 0, damagedCount = 0, lostPages = 0, lostCells = 0
    for (groupNumber, group) in file.groups.enumerated() {
        for (index, column) in columns.enumerated() {
            let chunk = group.chunks[index]
            var dictionary: [Value] = [], dictionaryDamaged = false
            var pages = chunk.pages.enumerated().map { (String($0.offset), $0.element) }
            if let page = chunk.dictionary { pages.insert(("dict", page), at: 0) }
            var row = group.firstRow
            for (pageNumber, page) in pages {
                examined += 1
                let checksum = adler32(file.body(page))
                let damaged = checksum != page.checksum
                if damaged {
                    damagedCount += 1
                    lines.append("damaged \(groupNumber) \(column.name) \(pageNumber) offset \(page.offset) stored \(checksumText(page.checksum)) computed \(checksumText(checksum))")
                }
                if pageNumber == "dict" {
                    dictionaryDamaged = damaged
                    if !damaged { dictionary = file.decodeDictionary(column, page) }
                    continue
                }
                let reason: String? = damaged ? "checksum" : page.method == .dictionary && dictionaryDamaged ? "dictionary" : nil
                if let reason {
                    lostPages += 1; lostCells += page.count
                    lines.append("lost \(groupNumber) \(column.name) \(pageNumber) rows \(page.count) reason \(reason)")
                } else {
                    for (offset, value) in file.decodePage(column, page, dictionary: dictionary).enumerated() { rows[row + offset][index] = value }
                }
                row += page.count
            }
        }
    }
    lines.append("summary pages \(examined) damaged \(damagedCount) lost_pages \(lostPages) lost_cells \(lostCells) recovered_cells \(file.rows * columns.count - lostCells)")
    let recovered = [columns.map(\.name).joined(separator: ",")] + rows.map { row in
        zip(columns, row).map { valueText($0.0.type, $0.1, null: "") }.joined(separator: ",")
    }
    return (lines, recovered)
}

let input = try Inputs()
let (data, encodingReport) = buildFile(input)
let file = ColumnarFile(data)
let metadata = verifyAndDescribe(file, original: input.rows)
let (queryResults, queryStatistics) = executeQueries(file, originals: input.rows, queries: input.queries)
let (recovery, recovered) = recover(input.damaged)
try writeOutputs([
    "file.hex": stride(from: 0, to: data.count, by: 32).map { hex(Array(data[$0..<min($0 + 32, data.count)])) },
    "metadata.txt": metadata, "encoding_report.csv": encodingReport, "query_results.txt": queryResults,
    "query_stats.txt": queryStatistics, "recovery.txt": recovery, "recovered.csv": recovered,
])

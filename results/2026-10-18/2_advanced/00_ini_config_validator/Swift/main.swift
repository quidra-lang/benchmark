import Foundation

func asciiText(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }
func isDigit(_ byte: UInt8) -> Bool { byte >= 48 && byte <= 57 }
func isLetter(_ byte: UInt8) -> Bool { (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) }

func fileLines(_ text: String) -> [String] {
    var lines = text.components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }
    return lines
}

func trimSpaces(_ text: String) -> String {
    text.trimmingCharacters(in: CharacterSet(charactersIn: " "))
}

func partition(_ text: String, at separator: String) -> (String, String?) {
    guard let range = text.range(of: separator) else { return (text, nil) }
    return (String(text[..<range.lowerBound]), String(text[range.upperBound...]))
}

func splitKey(_ key: String) -> (section: String, name: String) {
    let dot = key.lastIndex(of: ".")!
    return (String(key[..<dot]), String(key[key.index(after: dot)...]))
}

func keyLess(_ first: String, _ second: String) -> Bool {
    let a = splitKey(first), b = splitKey(second)
    return a.section == b.section ? a.name < b.name : a.section < b.section
}

struct Origin: Hashable {
    let document: String
    let line: Int
    var text: String { "\(document):\(line)" }
}

struct Diagnostic: Hashable {
    let origin: Origin
    let code: String
    let message: String
}

private func diagnosticLess(_ a: Diagnostic, _ b: Diagnostic) -> Bool {
    if a.origin.document != b.origin.document { return a.origin.document < b.origin.document }
    if a.origin.line != b.origin.line { return a.origin.line < b.origin.line }
    if a.code != b.code { return a.code < b.code }
    return a.message < b.message
}

struct Definition {
    let raw: String
    let origin: Origin
    let number: Int
    let history: [Origin]
}

indirect enum Value: Equatable {
    case string(String)
    case integer(Int64)
    case boolean(Bool)
    case atom(String)
    case list([Value])
}

struct OutputKey {
    let definition: Definition
    let spec: Spec?
    let value: Value
    let notation: String
}

private struct Parent {
    let section: String
    let origin: Origin
}

struct TreeLine {
    let depth: Int
    let text: String
}

private struct ValidationError: Error {
    let code: String
    let message: String
}

private func decimal(_ text: String, minimum: Int = 1, maximum: Int = 12) -> Int64? {
    let bytes = Array(text.utf8)
    guard bytes.count >= minimum, bytes.count <= maximum, bytes.allSatisfy(isDigit) else { return nil }
    return bytes.reduce(Int64(0)) { $0 * 10 + Int64($1 - 48) }
}

private func parseInteger(_ text: String) -> Int64? {
    let bytes = Array(text.utf8)
    var position = 0
    var sign: Int64 = 1
    if bytes.first == 43 || bytes.first == 45 {
        if bytes.first == 45 { sign = -1 }
        position = 1
    }
    var number: Int64 = 0
    if bytes.count - position >= 2 && bytes[position] == 48 &&
        (bytes[position + 1] == 120 || bytes[position + 1] == 88) {
        position += 2
        guard (1...10).contains(bytes.count - position) else { return nil }
        for byte in bytes[position...] {
            let digit: Int64
            if isDigit(byte) { digit = Int64(byte - 48) }
            else if byte >= 97 && byte <= 102 { digit = Int64(byte - 97 + 10) }
            else if byte >= 65 && byte <= 70 { digit = Int64(byte - 65 + 10) }
            else { return nil }
            number = number * 16 + digit
        }
    } else {
        var digits = 0
        var previousDigit = false
        while position < bytes.count {
            let byte = bytes[position]
            if isDigit(byte) {
                digits += 1
                guard digits <= 12 else { return nil }
                number = number * 10 + Int64(byte - 48)
                previousDigit = true
            } else if byte == 95 && previousDigit && position + 1 < bytes.count && isDigit(bytes[position + 1]) {
                previousDigit = false
            } else { return nil }
            position += 1
        }
        guard digits > 0 && previousDigit else { return nil }
    }
    return sign * number
}

private func parseSize(_ text: String) -> Int64? {
    let bytes = Array(text.utf8)
    var position = 0
    while position < bytes.count && isDigit(bytes[position]) { position += 1 }
    guard let whole = decimal(asciiText(Array(bytes[..<position])), maximum: 6) else { return nil }
    var fraction: Int64 = 0
    var divisor: Int64 = 1
    if position < bytes.count && bytes[position] == 46 {
        position += 1
        let start = position
        while position < bytes.count && isDigit(bytes[position]) { position += 1 }
        guard let parsed = decimal(asciiText(Array(bytes[start..<position])), maximum: 3) else { return nil }
        fraction = parsed
        for _ in start..<position { divisor *= 10 }
    }
    let unit = asciiText(Array(bytes[position...])).lowercased()
    let factor: Int64
    switch unit {
    case "", "b": factor = 1
    case "kb": factor = 1024
    case "mb": factor = 1048576
    case "gb": factor = 1073741824
    default: return nil
    }
    guard fraction * factor % divisor == 0 else { return nil }
    return whole * factor + fraction * factor / divisor
}

private func parseDuration(_ text: String) -> Int64? {
    if let seconds = decimal(text, maximum: 6) { return seconds }
    let bytes = Array(text.utf8)
    var position = 0
    var previous = -1
    var seconds: Int64 = 0
    while position < bytes.count {
        let start = position
        while position < bytes.count && isDigit(bytes[position]) { position += 1 }
        guard let part = decimal(asciiText(Array(bytes[start..<position])), maximum: 6),
              position < bytes.count else { return nil }
        let rank: Int
        switch bytes[position] {
        case 104: rank = 0
        case 109: rank = 1
        case 115: rank = 2
        default: return nil
        }
        guard rank > previous else { return nil }
        previous = rank
        seconds += part * (rank == 0 ? 3600 : rank == 1 ? 60 : 1)
        position += 1
    }
    return previous >= 0 ? seconds : nil
}

private func parseHost(_ text: String) -> String? {
    let labels = text.components(separatedBy: ".")
    if text.utf8.allSatisfy({ isDigit($0) || $0 == 46 }) {
        guard labels.count == 4 else { return nil }
        for label in labels {
            guard let number = decimal(label, maximum: 3), number <= 255,
                  label == "0" || !label.hasPrefix("0") else { return nil }
        }
        return text
    }
    guard text.utf8.count <= 253 else { return nil }
    for label in labels {
        guard (1...63).contains(label.utf8.count), !label.hasPrefix("-"), !label.hasSuffix("-"),
              label.utf8.allSatisfy({ isLetter($0) || isDigit($0) || $0 == 45 }) else { return nil }
    }
    return text.lowercased()
}

private func parsePath(_ text: String) -> String? {
    guard !text.isEmpty, !text.utf8.contains(where: { $0 == 32 || $0 == 10 || $0 == 9 }) else { return nil }
    let absolute = text.hasPrefix("/")
    var parts: [String] = []
    for part in text.components(separatedBy: "/") {
        if part.isEmpty || part == "." { continue }
        if part != ".." { parts.append(part) }
        else if !parts.isEmpty && parts.last != ".." { parts.removeLast() }
        else if absolute { return nil }
        else { parts.append(part) }
    }
    let joined = parts.joined(separator: "/")
    return absolute ? "/" + joined : parts.isEmpty ? "." : joined
}

private func parseURL(_ text: String) -> String? {
    let (schemeText, restText) = partition(text, at: "://")
    guard let rest = restText, let first = schemeText.utf8.first, isLetter(first),
          schemeText.utf8.allSatisfy({ isLetter($0) || isDigit($0) || [43, 45, 46].contains($0) }),
          !rest.contains("?"), !rest.contains("#") else { return nil }
    let (authority, pathPart) = partition(rest, at: "/")
    let (hostPart, portPart) = partition(authority, at: ":")
    guard let host = parseHost(hostPart), let path = parsePath("/" + (pathPart ?? "")) else { return nil }
    let scheme = schemeText.lowercased()
    var result = scheme + "://" + host
    if let port = portPart {
        guard let number = decimal(port, maximum: 5), !port.hasPrefix("0"), number <= 65535 else { return nil }
        if !((scheme == "http" && number == 80) || (scheme == "https" && number == 443)) {
            result += ":" + port
        }
    }
    return result + path
}

private func parseDate(_ text: String) -> String? {
    let bytes = Array(text.utf8)
    guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
          let year = decimal(asciiText(Array(bytes[0..<4])), minimum: 4, maximum: 4), year >= 1,
          let month = decimal(asciiText(Array(bytes[5..<7])), minimum: 2, maximum: 2),
          (1...12).contains(month),
          let day = decimal(asciiText(Array(bytes[8..<10])), minimum: 2, maximum: 2) else { return nil }
    var days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][Int(month) - 1]
    if month == 2 && ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) { days += 1 }
    return day >= 1 && day <= Int64(days) ? text : nil
}

private func parseScalar(_ kind: Kind, text: String, choices: [String]) -> Value? {
    switch kind {
    case .string: return .string(text)
    case .int: return parseInteger(text).map(Value.integer)
    case .size: return parseSize(text).map(Value.integer)
    case .duration: return parseDuration(text).map(Value.integer)
    case .bool:
        switch text.lowercased() {
        case "true", "yes", "on", "1": return .boolean(true)
        case "false", "no", "off", "0": return .boolean(false)
        default: return nil
        }
    case .enumeration:
        return choices.first { $0.lowercased() == text.lowercased() }.map(Value.atom)
    case .host: return parseHost(text).map(Value.atom)
    case .path: return parsePath(text).map(Value.atom)
    case .url: return parseURL(text).map(Value.atom)
    case .date: return parseDate(text).map(Value.atom)
    case .list: return nil
    }
}

private func invalidValue(key: String, spec: Spec, kind: Kind, text: String, item: Bool) -> ValidationError {
    var display = spec.secret ? "********" : stringNotation(text)
    if item { display = "item " + display }
    if kind == .enumeration {
        return ValidationError(code: "E_ENUM", message: "\(key): \(display) is not one of " + spec.values.joined(separator: ","))
    }
    return ValidationError(code: "E_TYPE", message: "\(key): \(display) is not a valid \(kind.rawValue)")
}

private func checkRange(key: String, spec: Spec, value: Value) throws {
    guard let range = spec.range else { return }
    let measure: Int64
    let display: String
    switch value {
    case .string(let text):
        measure = Int64(text.utf8.count)
        display = "length \(measure)"
    case .list(let items):
        measure = Int64(items.count)
        display = "count \(measure)"
    case .integer(let number):
        measure = number
        display = spec.secret ? "********" : valueNotation(value)
    default:
        measure = 0
        display = spec.secret ? "********" : valueNotation(value)
    }
    var notations = ["", ""]
    var invalid = false
    for (index, text) in [range.lower, range.upper].enumerated() {
        if text.isEmpty { continue }
        let comparison: Int
        if spec.kind == .date {
            guard case .atom(let date) = value else { preconditionFailure() }
            notations[index] = text
            comparison = date < text ? -1 : date > text ? 1 : 0
        } else {
            let bound: Int64
            if spec.kind == .string || spec.kind == .list { bound = Int64(text)! }
            else {
                guard case .integer(let number)? = parseScalar(spec.kind, text: text, choices: []) else {
                    preconditionFailure()
                }
                bound = number
            }
            notations[index] = String(bound)
            comparison = measure < bound ? -1 : measure > bound ? 1 : 0
        }
        if (index == 0 && comparison < 0) || (index == 1 && comparison > 0) { invalid = true }
    }
    if invalid {
        throw ValidationError(code: "E_RANGE", message: "\(key): \(display) is out of range \(notations[0])..\(notations[1])")
    }
}

final class DocumentLibrary {
    private var documents: [String: Document] = [:]
    private var missing: Set<String> = []

    func find(_ name: String) -> Document? {
        if let document = documents[name] { return document }
        if missing.contains(name) { return nil }
        guard let text = try? String(contentsOfFile: "input/conf/\(name).ini", encoding: .ascii) else {
            missing.insert(name)
            return nil
        }
        let document = parseDocument(name: name, text: text)
        documents[name] = document
        return document
    }
}

final class Profile {
    let name: String
    let root: String
    let line: Int
    let overrides: [String]
    private var configuration: [String: Definition] = [:]
    private var definitionCount = 0
    private var parents: [String: Parent] = [:]
    private var diagnostics: Set<Diagnostic> = []
    private(set) var outputs: [String: OutputKey] = [:]
    private(set) var tree: [TreeLine] = []
    private(set) var sortedDiagnostics: [Diagnostic] = []
    private(set) var errors = 0
    private(set) var warnings = 0
    private(set) var documentKeys = 0
    private(set) var manifestKeys = 0
    private(set) var defaultKeys = 0
    private(set) var dropped = 0

    init(line: Int, text: String) {
        let words = text.components(separatedBy: " ")
        name = words[0]
        root = words[1]
        self.line = line
        overrides = Array(words.dropFirst(2))
    }

    private func report(_ origin: Origin, _ code: String, _ message: String) {
        diagnostics.insert(Diagnostic(origin: origin, code: code, message: message))
    }

    private func define(_ key: String, raw: String, origin: Origin) {
        definitionCount += 1
        var history = configuration[key]?.history ?? []
        if history.last != origin { history.append(origin) }
        configuration[key] = Definition(raw: raw, origin: origin, number: definitionCount, history: history)
    }

    func process(schema: Schema, library: DocumentLibrary, earlier: [Profile]) {
        apply(library: library, name: root, chain: [root])
        for override in overrides {
            let (key, value) = partition(override, at: "=")
            define(key, raw: value!, origin: Origin(document: "manifest", line: line))
        }
        inheritSections()
        resolveAliases(schema)
        let sections = fillDefaults(schema)
        let configured = Set(configuration.keys)
        checkTypes(schema)
        checkOrder()
        checkRequired(schema, sections: sections, configured: configured)
        checkFixed(earlier)
        sortedDiagnostics = diagnostics.sorted(by: diagnosticLess)
        errors = diagnostics.filter { $0.code.hasPrefix("E_") }.count
        warnings = diagnostics.count - errors
        for output in outputs.values {
            switch output.definition.origin.document {
            case "manifest": manifestKeys += 1
            case "schema": defaultKeys += 1
            default: documentKeys += 1
            }
        }
        dropped = configured.count - outputs.count
    }

    private func apply(library: DocumentLibrary, name: String, chain: [String]) {
        let document = library.find(name)!
        tree.append(TreeLine(depth: chain.count - 1, text: name))
        diagnostics.formUnion(document.diagnostics)
        for statement in document.statements {
            let origin = Origin(document: name, line: statement.line)
            switch statement.kind {
            case .assign:
                define(statement.target, raw: statement.value, origin: origin)
            case .append:
                var raw = statement.value
                if let existing = configuration[statement.target], !existing.raw.isEmpty {
                    raw = existing.raw + "," + raw
                }
                define(statement.target, raw: raw, origin: origin)
            case .unset:
                if configuration.removeValue(forKey: statement.target) == nil {
                    report(origin, "W_UNSET", "\(statement.target) is not set")
                }
            case .inherit:
                parents[statement.target] = Parent(section: statement.value, origin: origin)
            case .include:
                let target = statement.target
                if let start = chain.firstIndex(of: target) {
                    let path = Array(chain[start...]) + [target]
                    report(origin, "E_INCLUDE_CYCLE", "include cycle " + path.joined(separator: " -> "))
                    tree.append(TreeLine(depth: chain.count, text: target + " (cycle)"))
                } else if library.find(target) == nil {
                    report(origin, "E_INCLUDE_MISSING", "missing document " + target)
                    tree.append(TreeLine(depth: chain.count, text: target + " (missing)"))
                } else {
                    apply(library: library, name: target, chain: chain + [target])
                }
            }
        }
    }

    private func inheritSections() {
        let own = configuration
        for (section, declaration) in parents {
            var path = [section]
            var cycle = false
            while let parent = parents[path.last!] {
                if path.contains(parent.section) {
                    path.append(parent.section)
                    cycle = true
                    break
                }
                path.append(parent.section)
            }
            if cycle {
                report(declaration.origin, "E_INHERIT_CYCLE", "inheritance cycle " + path.joined(separator: " -> "))
                continue
            }
            if parents[declaration.section] == nil && !own.keys.contains(where: { splitKey($0).section == declaration.section }) {
                report(declaration.origin, "W_PARENT_EMPTY", "section \(section) inherits from empty section \(declaration.section)")
            }
            for ancestor in path.dropFirst() {
                for (key, definition) in own where splitKey(key).section == ancestor {
                    let target = section + "." + splitKey(key).name
                    if configuration[target] == nil { configuration[target] = definition }
                }
            }
        }
    }

    private func resolveAliases(_ schema: Schema) {
        for spec in schema.specs {
            let aliases = spec.aliases.filter { configuration[$0] != nil }
            if aliases.isEmpty { continue }
            let candidates = (configuration[spec.pattern] == nil ? [] : [spec.pattern]) + aliases
            var winner = candidates[0]
            for candidate in candidates.dropFirst() {
                if configuration[candidate]!.number > configuration[winner]!.number { winner = candidate }
            }
            let chosen = configuration[winner]!
            for candidate in candidates {
                let origin = configuration[candidate]!.origin
                if candidate != spec.pattern {
                    report(origin, "W_DEPRECATED", "\(candidate) is deprecated, use \(spec.pattern)")
                }
                if candidate != winner {
                    report(origin, "W_SHADOWED", "\(candidate) is superseded by \(winner) at \(chosen.origin.text)")
                }
            }
            configuration[spec.pattern] = chosen
            for alias in aliases { configuration.removeValue(forKey: alias) }
        }
    }

    private func fillDefaults(_ schema: Schema) -> Set<String> {
        let sections = Set(configuration.keys.map { splitKey($0).section })
        for spec in schema.specs {
            guard let raw = spec.defaultValue else { continue }
            for key in schema.targetKeys(for: spec, sections: sections) where configuration[key] == nil {
                define(key, raw: raw, origin: Origin(document: "schema", line: spec.line))
            }
        }
        return sections
    }

    private func checkTypes(_ schema: Schema) {
        let expanded = expandConfiguration(configuration) { origin, code, message in
            self.report(origin, code, message)
        }
        for key in configuration.keys.sorted(by: keyLess) {
            guard let text = expanded[key] else { continue }
            let definition = configuration[key]!
            let spec = schema.spec(for: key)
            let value: Value
            if let spec {
                do {
                    value = try normalize(key: key, spec: spec, text: text, origin: definition.origin)
                } catch let error as ValidationError {
                    report(definition.origin, error.code, error.message)
                    continue
                } catch {
                    preconditionFailure("unexpected validation error")
                }
            } else {
                report(definition.origin, "W_UNKNOWN", "\(key) is not in the schema")
                value = .string(text)
            }
            outputs[key] = OutputKey(definition: definition, spec: spec, value: value, notation: valueNotation(value))
        }
    }

    private func normalize(key: String, spec: Spec, text: String, origin: Origin) throws -> Value {
        let value: Value
        if spec.kind == .list {
            var values: [Value] = []
            if !trimSpaces(text).isEmpty {
                let items = text.components(separatedBy: ",").map(trimSpaces)
                if items.contains("") { report(origin, "W_EMPTY_ITEM", "\(key): empty list item ignored") }
                for item in items where !item.isEmpty {
                    guard let parsed = parseScalar(spec.item, text: item, choices: spec.values) else {
                        throw invalidValue(key: key, spec: spec, kind: spec.item, text: item, item: true)
                    }
                    values.append(parsed)
                }
                if spec.unique {
                    var unique: [Value] = []
                    for item in values where !unique.contains(item) { unique.append(item) }
                    if unique.count != values.count {
                        report(origin, "W_DUPLICATE_ITEM", "\(key): duplicate items removed")
                    }
                    values = unique
                }
            }
            value = .list(values)
        } else {
            guard let parsed = parseScalar(spec.kind, text: text, choices: spec.values) else {
                throw invalidValue(key: key, spec: spec, kind: spec.kind, text: text, item: false)
            }
            value = parsed
        }
        try checkRange(key: key, spec: spec, value: value)
        return value
    }

    private func checkOrder() {
        var removed: [String] = []
        for key in outputs.keys.sorted(by: keyLess) {
            let output = outputs[key]!
            guard let le = output.spec?.le else { continue }
            let limitKey = splitKey(key).section + "." + le
            guard let limit = outputs[limitKey], case .integer(let number) = output.value,
                  case .integer(let maximum) = limit.value, number > maximum else { continue }
            report(output.definition.origin, "E_ORDER", "\(key): \(shown(output)) is greater than \(limitKey) (\(shown(limit)))")
            removed.append(key)
        }
        for key in removed { outputs.removeValue(forKey: key) }
    }

    private func checkRequired(_ schema: Schema, sections: Set<String>, configured: Set<String>) {
        for spec in schema.specs where spec.required {
            for key in schema.targetKeys(for: spec, sections: sections) where !configured.contains(key) {
                var message = "\(key) is required"
                if let when = spec.when {
                    let condition = splitKey(key).section + "." + when
                    guard outputs[condition]?.value == .boolean(true) else { continue }
                    message = "\(key) is required when \(condition) is true"
                }
                report(Origin(document: root, line: 0), "E_REQUIRED", message)
            }
        }
    }

    private func checkFixed(_ earlier: [Profile]) {
        for key in outputs.keys.sorted(by: keyLess) {
            let output = outputs[key]!
            guard output.spec?.fixed == true,
                  let reference = earlier.first(where: { $0.outputs[key] != nil }),
                  output.notation != reference.outputs[key]!.notation else { continue }
            report(output.definition.origin, "E_FIXED", "\(key): value differs from profile \(reference.name)")
            outputs.removeValue(forKey: key)
        }
    }
}

struct DiffEntry {
    let mark: String
    let key: String
    let before: OutputKey?
    let after: OutputKey?
}

struct ProfileDiff {
    let first: String
    let second: String
    var added = 0
    var removed = 0
    var changed = 0
    var entries: [DiffEntry] = []

    init(first: Profile, second: Profile) {
        self.first = first.name
        self.second = second.name
        let keys = Set(first.outputs.keys).union(second.outputs.keys).sorted(by: keyLess)
        for key in keys {
            let before = first.outputs[key], after = second.outputs[key]
            let mark: String
            if before == nil { mark = "+"; added += 1 }
            else if after == nil { mark = "-"; removed += 1 }
            else if before!.notation != after!.notation { mark = "~"; changed += 1 }
            else { continue }
            entries.append(DiffEntry(mark: mark, key: key, before: before, after: after))
        }
    }
}

func run() throws {
    let schema = try Schema(path: "input/schema.txt")
    let library = DocumentLibrary()
    let manifest = try String(contentsOfFile: "input/manifest.txt", encoding: .ascii)
    var profiles: [Profile] = []
    for (index, line) in fileLines(manifest).enumerated() {
        let profile = Profile(line: index + 1, text: line)
        profile.process(schema: schema, library: library, earlier: profiles)
        profiles.append(profile)
    }
    let diffs = zip(profiles, profiles.dropFirst()).map { ProfileDiff(first: $0.0, second: $0.1) }
    try writeOutputs(profiles: profiles, diffs: diffs)
}

try run()

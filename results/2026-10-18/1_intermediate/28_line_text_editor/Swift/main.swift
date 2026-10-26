import Foundation

struct EditorError: Error {
    let reason: String
    init(_ reason: String) {
        self.reason = reason
    }
}

func isDigit(_ ch: Character) -> Bool {
    ch >= "0" && ch <= "9"
}
func isLower(_ ch: Character) -> Bool {
    ch >= "a" && ch <= "z"
}
func isUpper(_ ch: Character) -> Bool {
    ch >= "A" && ch <= "Z"
}

typealias Replacement = [Character?]

struct Delimited {
    let text: String
    let replacement: Replacement
    let raw: String
    let next: Int
}

func readDelimited(_ source: [Character], from start: Int, delimiter: Character) throws -> Delimited {
    var text = "", replacement: Replacement = []
    var i = start
    while i < source.count {
        let ch = source[i]
        if ch == "\\" {
            i += 1
            guard i < source.count else {
                throw EditorError("missing delimiter")
            }
            text.append(source[i])
            replacement.append(source[i])
        } else if ch == delimiter {
            return Delimited(text: text, replacement: replacement, raw: String(source[start..<i]), next: i + 1)
        } else {
            text.append(ch)
            replacement.append(ch == "&" ? nil : ch)
        }
        i += 1
    }
    throw EditorError("missing delimiter")
}

enum Element {
    case number(Int), offset(Int), current, last, separator(Character), all, mark(String), search(String, forward: Bool)
}

struct AddressScan {
    let elements: [Element]
    let command: String
}

func scanAddress(_ text: String) throws -> AddressScan {
    let source = Array(text)
    var elements: [Element] = []
    var i = 0
    while i < source.count {
        let ch = source[i]
        if isDigit(ch) || ch == "+" || ch == "-" {
            let start = i
            i += 1
            while i < source.count && isDigit(source[i]) {
                i += 1
            }
            if isDigit(ch) {
                elements.append(.number(Int(String(source[start..<i]))!))
            } else {
                let magnitude = i == start + 1 ? 1 : Int(String(source[(start + 1)..<i]))!
                elements.append(.offset(ch == "+" ? magnitude : -magnitude))
            }
        } else if ".$,;%".contains(ch) {
            switch ch {
            case ".":
                elements.append(.current)
            case "$":
                elements.append(.last)
            case ",", ";":
                elements.append(.separator(ch))
            default:
                elements.append(.all)
            }
            i += 1
        } else if ch == "'" {
            i += 1
            elements.append(.mark(i < source.count ? String(source[i]) : ""))
            if i < source.count {
                i += 1
            }
        } else if ch == "/" || ch == "?" {
            let found = try readDelimited(source, from: i + 1, delimiter: ch)
            elements.append(.search(found.text, forward: ch == "/"))
            i = found.next
        } else {
            break
        }
    }
    return AddressScan(elements: elements, command: String(source[i...]))
}

func singleAddress(_ elements: [Element]) -> Bool {
    if elements.isEmpty {
        return false
    }
    for (i, element) in elements.enumerated() {
        switch element {
        case .offset:
            continue
        case .separator, .all:
            return false
        default:
            if i != 0 {
                return false
            }
        }
    }
    return true
}

struct AddressForm {
    var count = 0
    var left: [Element] = []
    var right: [Element] = []
    var separator: Character = ","
}

func addressForm(_ elements: [Element]) throws -> AddressForm {
    if elements.isEmpty {
        return AddressForm()
    }
    if elements.count == 1, case .all = elements[0] {
        return AddressForm(count: 2, left: [.number(1)], right: [.last])
    }
    var separator: Int?
    for (i, element) in elements.enumerated() {
        if case .separator = element {
            if separator != nil {
                throw EditorError("bad address")
            }
            separator = i
        }
    }
    guard let index = separator else {
        guard singleAddress(elements) else {
            throw EditorError("bad address")
        }
        return AddressForm(count: 1, left: elements)
    }
    let left = Array(elements[..<index]), right = Array(elements[(index + 1)...])
    guard (left.isEmpty || singleAddress(left)) && (right.isEmpty || singleAddress(right)) else {
        throw EditorError("bad address")
    }
    if case let .separator(ch) = elements[index] {
        return AddressForm(count: 2, left: left, right: right, separator: ch)
    }
    preconditionFailure("Expected separator")
}

enum Kind {
    case bare, append, insert, change, print, numbered, list, position, count, yank, marks, history, files
    case erase, put, join, joinWords, scroll, indent, unindent, undo, letterCase, redo, read, writePrint
    case write, writeAppend, edit, mark, move, copy, substitute, global, inverseGlobal, sort
}

final class Command {
    let kind: Kind
    var suffix: Character?
    var amount: Int?
    var argument = ""
    var destination: [Element] = []
    var pattern = ""
    var replacement: Replacement?
    var allMatches = false
    var occurrence = 1
    var subcommand: Command?
    init(_ kind: Kind) {
        self.kind = kind
    }
}

func positiveArgument(_ argument: String) throws -> Int? {
    if argument.isEmpty {
        return nil
    }
    guard argument.allSatisfy(isDigit), let value = Int(argument),
          value > 0
    else {
        throw EditorError("invalid suffix")
    }
    return value
}

func printSuffix(_ argument: String) throws -> Character? {
    if argument.isEmpty {
        return nil
    }
    guard argument.count == 1, let ch = argument.first, "pnl".contains(ch) else {
        throw EditorError("invalid suffix")
    }
    return ch
}

func fileName(_ argument: String) throws -> String {
    guard (2...9).contains(argument.count), argument.first == " ",
          argument.dropFirst().allSatisfy({ isLower($0) || isDigit($0) })
    else {
        throw EditorError("invalid file name")
    }
    return String(argument.dropFirst())
}

func parseSubstitution(_ argument: String) throws -> Command {
    let command = Command(.substitute)
    var flags = Array(argument)
    if !argument.allSatisfy({ isDigit($0) || "gpnl".contains($0) }) {
        let source = Array(argument), delimiter = argument.first!
        if delimiter == " " || delimiter == "\\" {
            throw EditorError("missing delimiter")
        }
        let search = try readDelimited(source, from: 1, delimiter: delimiter)
        let replacement = try readDelimited(source, from: search.next, delimiter: delimiter)
        command.pattern = search.text
        if replacement.raw != "%" {
            command.replacement = replacement.replacement
        }
        flags = Array(source[replacement.next...])
    }
    var i = 0, counted = false
    while i < flags.count {
        let ch = flags[i]
        i += 1
        if ch == "g" {
            if command.allMatches {
                throw EditorError("invalid suffix")
            }
            command.allMatches = true
        } else if "pnl".contains(ch) {
            if command.suffix != nil {
                throw EditorError("invalid suffix")
            }
            command.suffix = ch
        } else if isDigit(ch) {
            if counted {
                throw EditorError("invalid suffix")
            }
            let start = i - 1
            while i < flags.count && isDigit(flags[i]) {
                i += 1
            }
            command.occurrence = Int(String(flags[start..<i]))!
            if command.occurrence == 0 {
                throw EditorError("invalid suffix")
            }
            counted = true
        } else {
            throw EditorError("invalid suffix")
        }
    }
    return command
}

func sortForm(_ source: String) -> Bool {
    source == "sort" || source.hasPrefix("sort ")
}

func parseCommand(_ source: String) throws -> Command {
    if sortForm(source) {
        let command = Command(.sort)
        command.argument = source == "sort" ? "" : String(source.dropFirst(5))
        if source != "sort" {
            let options = command.argument
            guard !options.isEmpty, options.allSatisfy({ "ruin".contains($0) }), Set(options).count == options.count,
                  !(options.contains("i") && options.contains("n"))
            else {
                throw EditorError("invalid suffix")
            }
        }
        return command
    }
    guard let ch = source.first else {
        return Command(.bare)
    }
    let argument = String(source.dropFirst())
    let plain: [Character: Kind] = [
        "a": .append, "i": .insert, "c": .change, "p": .print, "n": .numbered, "l": .list,
        "=": .position, "#": .count, "y": .yank, "K": .marks, "h": .history, "f": .files
    ]
    if let kind = plain[ch] {
        if !argument.isEmpty {
            throw EditorError("invalid suffix")
        }
        return Command(kind)
    }
    if "dxjJ".contains(ch) {
        let command = Command(ch == "d" ? .erase : ch == "x" ? .put : ch == "j" ? .join : .joinWords)
        command.suffix = try printSuffix(argument)
        return command
    }
    if "z><u".contains(ch) {
        let command = Command(ch == "z" ? .scroll : ch == ">" ? .indent : ch == "<" ? .unindent : .undo)
        command.amount = try positiveArgument(argument)
        return command
    }
    if ch == "~" {
        guard argument.isEmpty || argument == "u" || argument == "l" else {
            throw EditorError("invalid suffix")
        }
        let command = Command(.letterCase)
        command.argument = argument
        return command
    }
    if ch == "r" && argument.allSatisfy(isDigit) {
        let command = Command(.redo)
        command.amount = try positiveArgument(argument)
        return command
    }
    if ch == "w" && argument.isEmpty {
        return Command(.writePrint)
    }
    if "rwWe".contains(ch) {
        let command = Command(ch == "r" ? .read : ch == "w" ? .write : ch == "W" ? .writeAppend : .edit)
        command.argument = try fileName(argument)
        return command
    }
    if ch == "k" {
        guard argument.count == 1, let mark = argument.first, isLower(mark) else {
            throw EditorError("invalid mark")
        }
        let command = Command(.mark)
        command.argument = argument
        return command
    }
    if ch == "m" || ch == "t" {
        let destination = try scanAddress(argument)
        guard singleAddress(destination.elements) else {
            throw EditorError("invalid destination")
        }
        let command = Command(ch == "m" ? .move : .copy)
        command.destination = destination.elements
        command.suffix = try printSuffix(destination.command)
        return command
    }
    if ch == "s" {
        return try parseSubstitution(argument)
    }
    if ch == "g" || ch == "v" {
        guard let delimiter = argument.first, delimiter != " ",
              delimiter != "\\"
        else {
            throw EditorError("missing delimiter")
        }
        let chars = Array(argument)
        let search = try readDelimited(chars, from: 1, delimiter: delimiter)
        let subcommand = search.next == chars.count ? "p" : String(chars[search.next...])
        guard "pnldmtjJs><~aicx".contains(subcommand.first!),
              !sortForm(subcommand)
        else {
            throw EditorError("invalid global command")
        }
        let command = Command(ch == "g" ? .global : .inverseGlobal)
        command.pattern = search.text
        command.subcommand = try parseCommand(subcommand)
        return command
    }
    throw EditorError("unknown command")
}

func hasText(_ source: String) -> Bool {
    do {
        let command = Array(try scanAddress(source).command)
        if command.count == 1 && "aic".contains(command[0]) {
            return true
        }
        guard command.count >= 2, "gv".contains(command[0]), command[1] != " ", command[1] != "\\" else {
            return false
        }
        let search = try readDelimited(command, from: 2, delimiter: command[1])
        return search.next + 1 == command.count && "aic".contains(command[search.next])
    } catch { return false }
}

func addressKind(_ kind: Kind) -> Int {
    switch kind {
    case .undo, .redo, .history, .marks, .files, .edit:
        return 0
    case .append, .insert, .put, .position, .read, .mark, .scroll:
        return 1
    default:
        return 2
    }
}

func modifying(_ command: Command) -> Bool {
    switch command.kind {
    case .global, .inverseGlobal:
        return ![Kind.print, .numbered, .list].contains(command.subcommand!.kind)
    case .append, .insert, .change, .erase, .put, .join, .joinWords, .move, .copy, .substitute,
         .indent, .unindent, .letterCase, .sort, .read, .edit:
        return true
    default:
        return false
    }
}

struct Line {
    let id: Int
    var text: String
}

struct Record {
    let command: String
    let lines: [Line]
    let current: Int
}

struct EditorState {
    var lines: [Line] = []
    var current = 0
    var marks: [Character: Int] = [:]
    var cut: [String] = []
    var pattern: String?
    var replacement: Replacement?
    var displayCount = 5
    var undo: [Record] = []
    var redo: [Record] = []
    var files: [String: [String]] = [:]
    var nextID = 1
}

enum SortKey: Comparable {
    case number(Int), text(String)

    static func < (lhs: SortKey, rhs: SortKey) -> Bool {
        switch (lhs, rhs) {
        case let (.number(a), .number(b)):
            return a < b
        case let (.text(a), .text(b)):
            return a < b
        case (.number, .text):
            return true
        case (.text, .number):
            return false
        }
    }
}

struct KeyedLine {
    let line: Line
    let key: SortKey
    let position: Int
}

func byteCount(_ text: [String]) -> Int {
    text.reduce(0) { $0 + $1.utf8.count + 1 }
}

final class Editor {
    private var state = EditorState()
    private var output: [String] = []
    private var last: Int {
        state.lines.count
    }
    private func emit(_ text: String) {
        output.append(text)
    }

    private func newLines(_ text: [String]) -> [Line] {
        var lines: [Line] = []
        for value in text {
            lines.append(Line(id: state.nextID, text: value))
            state.nextID += 1
        }
        return lines
    }

    private func snapshot(_ command: String) -> Record {
        Record(
            command: command,
            lines: state.lines,
            current: state.current
        )
    }
    private func contents(_ a: Int, _ b: Int) -> [String] {
        state.lines[(a - 1)..<b].map(\.text)
    }

    private func replace(at position: Int, count: Int, with inserted: [Line]) {
        state.lines.replaceSubrange(position..<(position + count), with: inserted)
    }

    private func lineNumber(_ id: Int) -> Int {
        state.lines.firstIndex(where: { $0.id == id }).map { $0 + 1 } ?? 0
    }

    private func pattern(_ text: String) throws -> String {
        if !text.isEmpty {
            state.pattern = text
        }
        guard let pattern = state.pattern else {
            throw EditorError("no previous pattern")
        }
        return pattern
    }

    private func address(_ elements: [Element]) throws -> Int {
        var value = state.current, firstOffset = 1
        switch elements[0] {
        case let .number(number):
            value = number
        case .current:
            value = state.current
        case .last:
            value = last
        case let .mark(name):
            guard name.count == 1, let mark = name.first, isLower(mark) else {
                throw EditorError("invalid mark")
            }
            value = state.marks[mark].map(lineNumber) ?? 0
            if value == 0 {
                throw EditorError("mark not set")
            }
        case let .search(text, forward):
            let search = try pattern(text)
            value = 0
            for offset in 0..<last {
                let step = offset + 1
                let pivot = state.current == 0 && !forward ? last + 1 : state.current
                let index = forward ? (pivot + step - 1) % last : (pivot - step - 1 + last) % last
                if state.lines[index].text.contains(search) {
                    value = index + 1
                    break
                }
            }
            if value == 0 {
                throw EditorError("no match")
            }
        case .offset:
            firstOffset = 0
        default:
            preconditionFailure("Expected a single address")
        }
        for element in elements.dropFirst(firstOffset) {
            if case let .offset(delta) = element {
                value += delta
            }
        }
        return value
    }

    private func addresses(_ form: AddressForm) throws -> [Int] {
        if form.count == 0 {
            return []
        }
        if form.count == 1 {
            return [try address(form.left)]
        }
        let left = try (form.left.isEmpty ? (form.separator == "," ? 1 : state.current) : address(form.left))
        if form.separator == ";" {
            if left < 0 || left > last {
                throw EditorError("address out of range")
            }
            state.current = left
        }
        let right = try (form.right.isEmpty ? last : address(form.right))
        return [left, right]
    }

    private func range(_ command: Command, values: [Int]) throws -> (Int, Int) {
        let kind = command.kind, category = addressKind(kind)
        if category == 0 {
            return (0, 0)
        }
        if category == 1 {
            let fallback = kind == .position || kind == .read ? last : state.current + (kind == .scroll ? 1 : 0)
            let a = values.first ?? fallback
            let minimum = kind == .mark || kind == .scroll ? 1 : 0
            if a < minimum || a > last {
                throw EditorError("address out of range")
            }
            return (a, a)
        }
        let a: Int, b: Int
        if let first = values.first {
            a = first
            b = values.last!
        } else if [Kind.writePrint, .write, .writeAppend, .count].contains(kind) {
            return (1, last)
        } else if [Kind.global, .inverseGlobal, .sort].contains(kind) {
            a = 1
            b = last
        } else {
            a = state.current
            b = state.current + (kind == .join || kind == .joinWords ? 1 : 0)
        }
        if a < 1 || b < 1 || a > last || b > last {
            throw EditorError("address out of range")
        }
        if a > b || a == b && (kind == .join || kind == .joinWords) {
            throw EditorError("invalid range")
        }
        return (a, b)
    }

    private func printLine(_ number: Int, form: Character) {
        let text = state.lines[number - 1].text
        if form == "p" {
            emit(text)
        } else if form == "n" {
            let label = String(number)
            emit(String(repeating: " ", count: max(0, 3 - label.count)) + label + " " + text)
        } else {
            var escaped = text.replacingOccurrences(of: "\\", with: "\\\\") + "$"
            while escaped.count > 40 {
                emit(String(escaped.prefix(39)) + "\\")
                escaped = String(escaped.dropFirst(39))
            }
            emit(escaped)
        }
    }

    private func suffix(_ command: Command) {
        if let form = command.suffix, state.current > 0 {
            printLine(state.current, form: form)
        }
    }

    private func substitute(_ command: Command, from a: Int, through b: Int, insideGlobal: Bool) throws -> Int {
        let search = try pattern(command.pattern)
        guard let replacement = command.replacement ?? state.replacement
        else {
            throw EditorError("no previous substitution")
        }
        state.replacement = replacement
        let expanded = replacement.map { part in part.map { String($0) } ?? search }.joined()
        var changed = 0
        for i in (a - 1)..<b {
            let line = state.lines[i]
            var position = line.text.startIndex, occurrence = 0, result = "", substituted = false
            while let found = line.text.range(of: search, range: position..<line.text.endIndex) {
                occurrence += 1
                let replace = occurrence == command.occurrence || command.allMatches && occurrence > command.occurrence
                result += String(line.text[position..<found.lowerBound]) + (replace ? expanded : search)
                substituted = substituted || replace
                position = found.upperBound
            }
            if !substituted {
                continue
            }
            result += String(line.text[position...])
            if result.utf8.count > 80 {
                throw EditorError("line too long")
            }
            if result.isEmpty || result.last == " " {
                throw EditorError("bad line")
            }
            state.lines[i].text = result
            state.current = i + 1
            changed += 1
        }
        if changed == 0 && !insideGlobal {
            throw EditorError("no match")
        }
        if changed > 0 {
            suffix(command)
        }
        return changed
    }

    private func global(_ command: Command, from a: Int, through b: Int, text: [String]) throws {
        let search = try pattern(command.pattern)
        let selected = state.lines[(a - 1)..<b].filter { $0.text.contains(search) == (command.kind == .global) }
            .map(\.id)
        if selected.isEmpty {
            throw EditorError("no match")
        }
        let subcommand = command.subcommand!
        var changed = 0
        for id in selected {
            let number = lineNumber(id)
            if number == 0 {
                continue
            }
            state.current = number
            let (start, end) = try range(subcommand, values: [])
            changed += try execute(subcommand, from: start, through: end, text: text, insideGlobal: true)
        }
        if subcommand.kind == .substitute && changed == 0 {
            throw EditorError("no match")
        }
    }

    private func execute(_ command: Command, from a: Int, through b: Int, text: [String],
                         insideGlobal: Bool = false) throws -> Int
    {
        let kind = command.kind
        if kind == .substitute {
            return try substitute(command, from: a, through: b, insideGlobal: insideGlobal)
        }
        if kind == .global || kind == .inverseGlobal {
            try global(command, from: a, through: b, text: text)
        } else if [Kind.bare, .print, .numbered, .list].contains(kind) {
            let form: Character = kind == .numbered ? "n" : kind == .list ? "l" : "p"
            for i in (kind == .bare ? b : a)...b {
                printLine(i, form: form)
            }
            state.current = b
        } else if kind == .scroll {
            if let amount = command.amount {
                state.displayCount = amount
            }
            let end = min(a + state.displayCount - 1, last)
            for i in a...end {
                printLine(i, form: "p")
            }
            state.current = end
        } else if kind == .position {
            emit(String(a))
        } else if kind == .count {
            let text = contents(a, b)
            let words = text.reduce(0) { $0 + $1.split(separator: " ").count }
            let chars = text.reduce(0) { $0 + $1.utf8.count }
            emit("count lines=\(text.count) words=\(words) chars=\(chars)")
        } else if kind == .writePrint {
            let text = contents(a, b)
            for line in text {
                emit(line)
            }
            emit("lines=\(text.count) bytes=\(byteCount(text))")
        } else if kind == .append || kind == .insert {
            let position = kind == .append ? a : max(a, 1) - 1
            let inserted = newLines(text)
            replace(at: position, count: 0, with: inserted)
            state.current = position + inserted.count
        } else if kind == .change || kind == .erase {
            state.cut = contents(a, b)
            let inserted = kind == .change ? newLines(text) : []
            replace(at: a - 1, count: b - a + 1, with: inserted)
            state.current = inserted.isEmpty ? min(a, last) : a + inserted.count - 1
            suffix(command)
        } else if kind == .yank {
            state.cut = contents(a, b)
        } else if kind == .put {
            if state.cut.isEmpty {
                throw EditorError("nothing to put")
            }
            let inserted = newLines(state.cut)
            replace(at: a, count: 0, with: inserted)
            state.current = a + inserted.count
            suffix(command)
        } else if kind == .move || kind == .copy {
            let destination = try address(command.destination), count = b - a + 1
            if destination < 0 || destination > last {
                throw EditorError("address out of range")
            }
            if kind == .move {
                if a <= destination && destination < b {
                    throw EditorError("invalid destination")
                }
                let moved = Array(state.lines[(a - 1)..<b])
                replace(at: a - 1, count: count, with: [])
                let position = destination < a ? destination : destination - count
                replace(at: position, count: 0, with: moved)
                state.current = position + count
            } else {
                let copied = newLines(contents(a, b))
                replace(at: destination, count: 0, with: copied)
                state.current = destination + count
            }
            suffix(command)
        } else if kind == .join || kind == .joinWords {
            let text = contents(a, b)
            let joined = kind == .join ? text.joined()
                : text.enumerated().map { i, line in i == 0 ? line : String(line.drop(while: { $0 == " " })) }
                .joined(separator: " ")
            if joined.utf8.count > 80 {
                throw EditorError("line too long")
            }
            let line = Line(id: state.lines[a - 1].id, text: joined)
            replace(at: a - 1, count: b - a + 1, with: [line])
            state.current = a
            suffix(command)
        } else if kind == .indent || kind == .unindent || kind == .letterCase {
            let width = command.amount ?? 4
            for i in (a - 1)..<b {
                var value = state.lines[i].text
                if kind == .indent {
                    if value.utf8.count + width > 80 {
                        throw EditorError("line too long")
                    }
                    value = String(repeating: " ", count: width) + value
                } else if kind == .unindent {
                    let spaces = value.prefix(while: { $0 == " " }).count
                    value = String(value.dropFirst(min(width, spaces)))
                } else if command.argument == "u" {
                    value = value.uppercased()
                } else if command.argument == "l" {
                    value = value.lowercased()
                } else {
                    value = String(value.map { ch in
                        isLower(ch) ? Character(String(ch).uppercased()) : isUpper(ch) ?
                            Character(String(ch).lowercased()) : ch
                    })
                }
                state.lines[i].text = value
            }
            state.current = b
        } else if kind == .sort {
            let options = command.argument
            var sorted: [KeyedLine] = []
            for i in (a - 1)..<b {
                let line = state.lines[i]
                let key: SortKey
                if options.contains("n") {
                    let negative = line.text.first == "-"
                    let digits = line.text.dropFirst(negative ? 1 : 0).prefix(while: isDigit)
                    let number = digits.isEmpty ? 0 : Int(String(digits))! * (negative ? -1 : 1)
                    key = .number(number)
                } else {
                    key = .text(options.contains("i") ? line.text.lowercased() : line.text)
                }
                sorted.append(KeyedLine(line: line, key: key, position: i))
            }
            sorted.sort { x, y in
                if x.key == y.key {
                    return x.position < y.position
                }
                return options.contains("r") ? y.key < x.key : x.key < y.key
            }
            var lines: [Line] = [], previous: SortKey?
            for item in sorted {
                if options.contains("u") && previous == item.key {
                    continue
                }
                lines.append(item.line)
                previous = item.key
            }
            replace(at: a - 1, count: b - a + 1, with: lines)
            state.current = a + lines.count - 1
        } else if kind == .mark {
            state.marks[command.argument.first!] = state.lines[a - 1].id
        } else if kind == .marks {
            var marks: [String] = []
            for name in state.marks.keys.sorted() {
                let number = lineNumber(state.marks[name]!)
                if number > 0 {
                    marks.append("\(name)=\(number)")
                }
            }
            emit("marks " + (marks.isEmpty ? "none" : marks.joined(separator: " ")))
        } else if kind == .undo || kind == .redo {
            let count = command.amount ?? 1
            if count > (kind == .undo ? state.undo.count : state.redo.count) {
                throw EditorError(kind == .undo ? "nothing to undo" : "nothing to redo")
            }
            for _ in 0..<count {
                let record = kind == .undo ? state.undo.removeLast() : state.redo.removeLast()
                let reverse = snapshot(record.command)
                if kind == .undo {
                    state.redo.append(reverse)
                } else {
                    state.undo.append(reverse)
                }
                state.lines = record.lines
                state.current = record.current
            }
        } else if kind == .history {
            emit("history undo=\(state.undo.count) redo=\(state.redo.count)")
            for (name, history) in [("undo", state.undo), ("redo", state.redo)] {
                for (i, record) in history.reversed().enumerated() {
                    emit("\(name) \(i + 1): \(record.command)")
                }
            }
        } else if [Kind.write, .writeAppend, .read, .edit].contains(kind) {
            let file: [String]
            if kind == .write || kind == .writeAppend {
                file = (kind == .writeAppend ? state.files[command.argument] ?? [] : []) + contents(a, b)
                state.files[command.argument] = file
            } else {
                guard let stored = state.files[command.argument] else {
                    throw EditorError("no such file")
                }
                file = stored
                let inserted = newLines(file)
                if kind == .edit {
                    state.lines = inserted
                    state.current = inserted.count
                } else {
                    replace(at: a, count: 0, with: inserted)
                    state.current = a + inserted.count
                }
            }
            emit("file \(command.argument) lines=\(file.count) bytes=\(byteCount(file))")
        } else if kind == .files {
            let files = state.files.keys.sorted().map { "\($0)=\(state.files[$0]!.count)" }
            emit("files " + (files.isEmpty ? "none" : files.joined(separator: " ")))
        }
        return 0
    }

    func process(_ source: String, text: [String]) -> [String] {
        let previous = state
        let before = snapshot(source)
        output = []
        do {
            let scanned = try scanAddress(source)
            let form = try addressForm(scanned.elements)
            let command = try parseCommand(scanned.command)
            let category = addressKind(command.kind)
            if category == 0 && form.count > 0 {
                throw EditorError("unexpected address")
            }
            if category == 1 && form.count > 1 {
                throw EditorError("too many addresses")
            }
            let values = try addresses(form)
            let (a, b) = try range(command, values: values)
            _ = try execute(command, from: a, through: b, text: text)
            if last > 200 {
                throw EditorError("buffer full")
            }
            if modifying(command) {
                state.undo.append(before)
                state.redo = []
            }
            return output
        } catch let error as EditorError {
            state = previous
            return ["? " + error.reason]
        } catch { fatalError("Unexpected error: \(error)") }
    }
}

let editor = Editor()
var result: [String] = []
while let command = readLine(), command != "Q" {
    var text: [String] = []
    if hasText(command) {
        while let line = readLine(), line != "." {
            text.append(line)
        }
    }
    result.append(contentsOf: editor.process(command, text: text))
}
if !result.isEmpty {
    FileHandle.standardOutput.write(Data((result.joined(separator: "\n") + "\n").utf8))
}

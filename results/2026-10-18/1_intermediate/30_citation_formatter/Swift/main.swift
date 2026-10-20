import Foundation

enum Style: String, CaseIterable {
    case apa = "APA", ieee = "IEEE", chicago = "CHICAGO", mla = "MLA"
}
enum BibliographyError: Error { case invalid(String) }

let requiredFields: [String: [String]] = [
    "article": ["author", "title", "journal", "year"],
    "book": ["author", "title", "publisher", "year"],
    "inproceedings": ["author", "title", "booktitle", "year"],
    "incollection": ["author", "title", "booktitle", "publisher", "year"],
    "techreport": ["author", "title", "institution", "year"],
    "phdthesis": ["author", "title", "school", "year"],
    "misc": ["author", "title", "year"],
]
let fieldOrder = "author editor title journal booktitle edition volume number pages publisher institution school address howpublished month year doi note".components(separatedBy: " ")
let knownFields = Set(fieldOrder)
let smallWords = Set("a an and as at but by for from in into nor of on or over per so the to up via with yet".components(separatedBy: " "))
let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
let monthAbbreviations = Dictionary(uniqueKeysWithValues: zip(monthNames,
    ["Jan.", "Feb.", "Mar.", "Apr.", "May", "June", "July", "Aug.", "Sep.", "Oct.", "Nov.", "Dec."]))

func ascii<C: Collection>(_ bytes: C) -> String where C.Element == UInt8 {
    String(decoding: bytes, as: UTF8.self)
}
func isLetter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }
func isDigit(_ byte: UInt8) -> Bool { (48...57).contains(byte) }
func allDigits(_ text: String) -> Bool { !text.isEmpty && text.utf8.allSatisfy(isDigit) }
func lowerByte(_ byte: UInt8) -> UInt8 { (65...90).contains(byte) ? byte + 32 : byte }
func upperByte(_ byte: UInt8) -> UInt8 { (97...122).contains(byte) ? byte - 32 : byte }
func lower(_ text: String) -> String { ascii(text.utf8.map(lowerByte)) }
func plain(_ text: String) -> String { ascii(text.utf8.filter { $0 != 123 && $0 != 125 }) }
func letters(_ text: String) -> String { ascii(text.utf8.filter(isLetter).map(lowerByte)) }
func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespaces) }

func splitDepthZero(_ text: String, at separator: String) -> [String] {
    let bytes = Array(text.utf8), delimiter = Array(separator.utf8)
    var result: [String] = []
    var depth = 0, start = 0, position = 0
    while position < bytes.count {
        if depth == 0 && position + delimiter.count <= bytes.count &&
            bytes[position..<(position + delimiter.count)].elementsEqual(delimiter) {
            result.append(ascii(bytes[start..<position]))
            position += delimiter.count
            start = position
        } else {
            if bytes[position] == 123 { depth += 1 }
            if bytes[position] == 125 { depth -= 1 }
            position += 1
        }
    }
    result.append(ascii(bytes[start...]))
    return result
}

func accentAt(_ bytes: [UInt8], _ position: Int) -> (character: UInt8, length: Int)? {
    guard position + 1 < bytes.count, bytes[position] == 92 else { return nil }
    let command = bytes[position + 1]
    if command == 38 { return (38, 2) }
    let symbol = Array("'\"`^~=.".utf8).contains(command)
    if symbol && position + 2 < bytes.count && isLetter(bytes[position + 2]) {
        return (bytes[position + 2], 3)
    }
    if (symbol || Array("cuvH".utf8).contains(command)) && position + 4 < bytes.count &&
        bytes[position + 2] == 123 && isLetter(bytes[position + 3]) && bytes[position + 4] == 125 {
        return (bytes[position + 3], 5)
    }
    return nil
}

func normalize(_ text: String) -> String {
    let bytes = Array(text.utf8)
    var result: [UInt8] = [], position = 0
    while position < bytes.count {
        if bytes[position] == 123, let enclosed = accentAt(bytes, position + 1),
            position + enclosed.length + 1 < bytes.count, bytes[position + enclosed.length + 1] == 125 {
            result.append(enclosed.character)
            position += enclosed.length + 2
        } else if let accent = accentAt(bytes, position) {
            result.append(accent.character)
            position += accent.length
        } else {
            result.append(bytes[position] == 126 ? 32 : bytes[position])
            position += 1
        }
    }
    return ascii(result).components(separatedBy: " ").filter { !$0.isEmpty }.joined(separator: " ")
}

func evaluateExpression(_ expression: String, macros: [String: String]) throws -> String {
    var depth = 0
    for byte in expression.utf8 {
        if byte == 123 { depth += 1 }
        if byte == 125 { depth -= 1 }
        if depth < 0 { throw BibliographyError.invalid("unbalanced braces") }
    }
    guard depth == 0 else { throw BibliographyError.invalid("unbalanced braces") }
    var result = ""
    for term in expression.components(separatedBy: " # ") {
        if term.hasPrefix("{") || term.hasPrefix("\"") { result += String(term.dropFirst().dropLast()) }
        else if allDigits(term) { result += term }
        else {
            guard let value = macros[term] else { throw BibliographyError.invalid("unknown macro '\(term)'") }
            result += value
        }
    }
    return result
}

struct Person: Hashable {
    let first: String
    let von: String
    let last: String
    let junior: String

    init(_ text: String) {
        let parts = splitDepthZero(text, at: ",").map(trimmed)
        let words = splitDepthZero(parts[0], at: " ")
        let lowercase = words.indices.dropLast().filter { index in
            guard let byte = words[index].utf8.first else { return false }
            return (97...122).contains(byte)
        }
        if parts.count == 1 {
            let start = lowercase.first ?? (words.count - 1)
            let end = lowercase.last.map { $0 + 1 } ?? (words.count - 1)
            first = words[..<start].joined(separator: " ")
            von = words[start..<end].joined(separator: " ")
            last = words[end...].joined(separator: " ")
            junior = ""
        } else {
            let end = lowercase.last.map { $0 + 1 } ?? 0
            von = words[..<end].joined(separator: " ")
            last = words[end...].joined(separator: " ")
            first = parts.last!
            junior = parts.count == 3 ? parts[1] : ""
        }
    }

    var surname: String { plain(von.isEmpty ? last : von + " " + last) }
    var initials: String {
        let given = plain(first)
        if given.isEmpty { return "" }
        return given.components(separatedBy: " ").map { word in
            word.components(separatedBy: "-").map { piece in
                ascii([upperByte(piece.utf8.first(where: isLetter)!)]) + "."
            }.joined(separator: "-")
        }.joined(separator: " ")
    }
    func format(inverted: Bool, abbreviated: Bool) -> String {
        let given = abbreviated ? initials : plain(first)
        var result = surname
        if !first.isEmpty { result = inverted ? result + ", " + given : given + " " + result }
        if !junior.isEmpty { result += ", " + plain(junior) }
        return result
    }
}

struct NameList: Hashable {
    let names: [Person]
    let etAl: Bool
    init(_ text: String) {
        var parts = splitDepthZero(text, at: " and ")
        let marked = parts.last == "others"
        etAl = marked
        if marked { parts.removeLast() }
        names = parts.map(Person.init)
    }
    var singular: Bool { names.count == 1 && !etAl }
}

struct Entry {
    let key: String
    let type: String
    let fields: [String: String]
    let author: NameList?
    let editor: NameList?
    let primary: NameList
    let sortTitle: String
    let sortKey: [String]
    var suffix = ""

    init(key: String, type: String, fields: [String: String]) {
        let author = fields["author"].map(NameList.init)
        let editor = fields["editor"].map(NameList.init)
        let primary = author ?? editor!
        var title = lower(plain(fields["title"]!))
        for prefix in ["a ", "an ", "the "] where title.hasPrefix(prefix) {
            title = String(title.dropFirst(prefix.count))
            break
        }
        self.key = key
        self.type = type
        self.fields = fields
        self.author = author
        self.editor = editor
        self.primary = primary
        sortTitle = title
        sortKey = [lower(plain(primary.names[0].last)), plain(fields["year"]!), title, key]
    }
    func value(_ name: String) -> String { plain(fields[name] ?? "") }
    func yearLabel(_ style: Style) -> String { value("year") + (style == .apa || style == .chicago ? suffix : "") }
    var unknownFields: [String] { fields.keys.filter { !knownFields.contains($0) }.sorted() }
}

struct YearGroup: Hashable {
    let names: NameList
    let year: String
}

final class Database {
    let entries: [Entry]
    let byKey: [String: Int]
    let bibliography: [Int]

    init(lines: [String], output: inout [String]) {
        var entries: [Entry] = [], byKey: [String: Int] = [:]
        var macros = Dictionary(uniqueKeysWithValues: monthNames.map { (lower(String($0.prefix(3))), $0) })
        var errors = 0, position = 0
        func report(_ line: Int, _ name: String, _ reason: String) {
            output.append("ERROR line \(line): \(name): \(reason)")
            errors += 1
        }
        while position < lines.count {
            let line = lines[position]
            if line.isEmpty || line.hasPrefix("%") { position += 1; continue }
            if line.hasPrefix("@string{") {
                let separator = line.range(of: " = ")!
                let name = String(line[..<separator.lowerBound].dropFirst(8))
                let expression = String(line[separator.upperBound...].dropLast())
                do {
                    let value = try evaluateExpression(expression, macros: macros)
                    if macros[name] != nil { throw BibliographyError.invalid("duplicate macro") }
                    macros[name] = value
                } catch BibliographyError.invalid(let reason) { report(position + 1, name, reason) }
                catch { preconditionFailure("Unexpected database error") }
                position += 1
                continue
            }
            let opening = line.firstIndex(of: "{")!
            let type = String(line[..<opening].dropFirst())
            let key = String(line[line.index(after: opening)...].dropLast())
            var fields: [String: String] = [:]
            var failure: (line: Int, reason: String)?
            if requiredFields[type] == nil { failure = (position + 1, "unknown type '\(type)'") }
            else if byKey[key] != nil { failure = (position + 1, "duplicate key") }
            position += 1
            while lines[position] != "}" {
                if failure == nil {
                    let fieldLine = lines[position]
                    let separator = fieldLine.range(of: " = ")!
                    let name = String(fieldLine[..<separator.lowerBound].dropFirst(2))
                    var expression = String(fieldLine[separator.upperBound...])
                    if expression.hasSuffix(",") { expression.removeLast() }
                    do {
                        let value = try evaluateExpression(expression, macros: macros)
                        if fields[name] != nil { throw BibliographyError.invalid("duplicate field '\(name)'") }
                        fields[name] = normalize(value)
                    } catch BibliographyError.invalid(let reason) { failure = (position + 1, reason) }
                    catch { preconditionFailure("Unexpected database error") }
                }
                position += 1
            }
            if failure == nil {
                for name in requiredFields[type]! where fields[name] == nil {
                    if type == "book" && name == "author" && fields["editor"] != nil { continue }
                    failure = (position + 1, "missing field '\(name)'")
                    break
                }
            }
            if let failure { report(failure.line, key, failure.reason) }
            else {
                byKey[key] = entries.count
                entries.append(Entry(key: key, type: type, fields: fields))
            }
            position += 1
        }
        output.append("LOADED entries=\(entries.count) macros=\(macros.count - 12) errors=\(errors)")
        var groups: [YearGroup: [Int]] = [:]
        for index in entries.indices {
            let group = YearGroup(names: entries[index].primary, year: entries[index].fields["year"]!)
            groups[group, default: []].append(index)
        }
        for group in groups.values where group.count > 1 {
            let sorted = group.sorted { a, b in
                [entries[a].sortTitle, entries[a].key].lexicographicallyPrecedes([entries[b].sortTitle, entries[b].key])
            }
            for (suffix, index) in sorted.enumerated() { entries[index].suffix = String(UnicodeScalar(97 + suffix)!) }
        }
        self.entries = entries
        self.byKey = byKey
        bibliography = entries.indices.sorted { entries[$0].sortKey.lexicographicallyPrecedes(entries[$1].sortKey) }
    }
}

func listNames(_ names: [String], conjunction: String, listB: Bool = false) -> String {
    if names.count == 1 { return names[0] }
    if listB && names.count == 2 { return names.joined(separator: " \(conjunction) ") }
    return names.dropLast().joined(separator: ", ") + ", " + conjunction + " " + names.last!
}

func authorValue(_ entry: Entry, style: Style, repeated: Bool) -> String {
    let list = entry.primary
    var result = "---"
    if !repeated {
        let names = list.names.enumerated().map { index, person in
            person.format(inverted: style == .apa || (style != .ieee && index == 0),
                          abbreviated: style == .apa || style == .ieee)
        }
        switch style {
        case .apa:
            if list.etAl { result = names.joined(separator: ", ") + ", et al." }
            else if names.count <= 20 { result = listNames(names, conjunction: "&") }
            else { result = names.prefix(19).joined(separator: ", ") + ", . . . " + names.last! }
        case .ieee:
            result = list.etAl || names.count >= 7 ? names[0] + " et al." : listNames(names, conjunction: "and", listB: true)
        case .chicago:
            result = list.etAl || names.count >= 11 ? names.prefix(7).joined(separator: ", ") + ", et al." : listNames(names, conjunction: "and")
        case .mla:
            result = list.etAl || names.count >= 3 ? names[0] + ", et al." : listNames(names, conjunction: "and")
        }
    }
    if entry.author == nil {
        switch style {
        case .apa: result += list.singular ? " (Ed.)" : " (Eds.)"
        case .ieee: result += list.singular ? ", Ed." : ", Eds."
        case .chicago: result += list.singular ? ", ed." : ", eds."
        case .mla: result += list.singular ? ", editor" : ", editors"
        }
    }
    return result
}

func editorValue(_ list: NameList?, style: Style) -> String {
    guard let list else { return "" }
    let names = list.names.map { $0.format(inverted: false, abbreviated: style == .apa || style == .ieee) }
    return list.etAl ? names[0] + " et al." : listNames(names, conjunction: style == .apa ? "&" : "and", listB: true)
}

func titleValue(_ title: String, style: Style) -> String {
    if style == .ieee { return plain(title) }
    if style == .apa {
        let original = Array(title.utf8)
        var result = original, depth = 0
        for index in original.indices {
            let byte = original[index]
            if byte == 123 { depth += 1 }
            if byte == 125 { depth -= 1 }
            if depth == 0 && isLetter(byte) {
                let upper = index == 0 || (index >= 2 && original[index - 2] == 58 && original[index - 1] == 32)
                result[index] = upper ? upperByte(byte) : lowerByte(byte)
            }
        }
        return plain(ascii(result))
    }
    let words = splitDepthZero(title, at: " ")
    let result = words.enumerated().map { index, word -> String in
        if word.hasPrefix("{") { return word }
        let makeLower = index > 0 && index + 1 < words.count && !words[index - 1].hasSuffix(":") && smallWords.contains(letters(word))
        var bytes = Array(word.utf8), depth = 0, firstLetter = true
        for i in bytes.indices {
            let byte = bytes[i]
            if byte == 123 { depth += 1 }
            if byte == 125 { depth -= 1 }
            if !isLetter(byte) { continue }
            if depth == 0 {
                if makeLower { bytes[i] = lowerByte(byte) }
                else if firstLetter { bytes[i] = upperByte(byte) }
            }
            firstLetter = false
        }
        return ascii(bytes)
    }
    return plain(result.joined(separator: " "))
}

func ordinal(_ text: String) -> String {
    let number = Int(text)!
    let lastTwo = number % 100
    let suffix = (11...13).contains(lastTwo) ? "th" : ([1: "st", 2: "nd", 3: "rd"][number % 10] ?? "th")
    return text + suffix
}

func placeholderValues(_ entry: Entry, style: Style, repeated: Bool) -> [String: String] {
    var values = entry.fields.mapValues(plain)
    values["author"] = authorValue(entry, style: style, repeated: repeated)
    values["editor"] = editorValue(entry.editor, style: style)
    values["eds"] = entry.editor.map { $0.singular ? "Ed." : "Eds." } ?? ""
    values["title"] = titleValue(entry.fields["title"]!, style: style)
    values["year"] = entry.yearLabel(style)
    let pages = entry.value("pages").components(separatedBy: "--").joined(separator: "-")
    values["pages"] = pages
    values["pp"] = entry.fields["pages"] == nil ? "" : (pages.contains("-") ? "pp. " : "p. ") + pages
    let edition = entry.value("edition")
    values["edition"] = entry.fields["edition"] == nil ? "" : (allDigits(edition) ? ordinal(edition) : edition) + " ed."
    let month = entry.value("month")
    values["mon"] = monthAbbreviations[month] ?? month
    return values
}

indirect enum TemplateNode {
    case literal(String)
    case value(String)
    case optional([TemplateNode])
}

func parseTemplate(_ source: String) -> [TemplateNode] {
    let bytes = Array(source.utf8)
    var position = 0
    func sequence() -> [TemplateNode] {
        var nodes: [TemplateNode] = []
        while position < bytes.count && bytes[position] != 62 {
            if bytes[position] == 60 {
                position += 1
                nodes.append(.optional(sequence()))
                position += 1
            } else if bytes[position] == 123 {
                let end = bytes[position...].firstIndex(of: 125)!
                nodes.append(.value(ascii(bytes[(position + 1)..<end])))
                position = end + 1
            } else {
                let start = position
                position += 1
                while position < bytes.count && ![60, 62, 123].contains(bytes[position]) { position += 1 }
                nodes.append(.literal(ascii(bytes[start..<position])))
            }
        }
        return nodes
    }
    return sequence()
}

func renderTemplate(_ nodes: [TemplateNode], values: [String: String]) -> String {
    var result = ""
    func visit(_ nodes: [TemplateNode]) {
        for node in nodes {
            switch node {
            case .value(let name): result += values[name] ?? ""
            case .optional(let children):
                let present = children.allSatisfy { child in
                    if case .value(let name) = child { return !(values[name] ?? "").isEmpty }
                    return true
                }
                if present { visit(children) }
            case .literal(let text):
                for character in text {
                    if character != "." || (result.last.map { !".?!".contains($0) } ?? true) { result.append(character) }
                }
            }
        }
    }
    visit(nodes)
    return result
}

let templateSources: [Style: [String: String]] = [
    .apa: [
        "article": "{author}. ({year}). {title}. {journal}<, {volume}<({number})>><, {pages}>.< https://doi.org/{doi}>",
        "book": "{author}. ({year}). {title}< ({edition})>. {publisher}.",
        "inproceedings": "{author}. ({year}). {title}. In <{editor} ({eds}), >{booktitle}< ({pp})>.< {publisher}.>",
        "techreport": "{author}. ({year}). {title}< (Report No. {number})>. {institution}.",
        "phdthesis": "{author}. ({year}). {title} [Doctoral dissertation, {school}].",
        "misc": "{author}. ({year}<, {month}>). {title}.< {howpublished}.>< {note}.>",
    ],
    .ieee: [
        "article": "{author}, \"{title},\" {journal}<, vol. {volume}><, no. {number}><, {pp}>, <{mon} >{year}<, doi: {doi}>.",
        "book": "{author}, {title}<, {edition}>. <{address}: >{publisher}, {year}.",
        "inproceedings": "{author}, \"{title},\" in {booktitle}<, {editor}, {eds}><, {address}><, {publisher}>, {year}<, {pp}>.",
        "techreport": "{author}, \"{title},\" {institution}<, {address}>, Tech. Rep.< {number}>, {year}.",
        "phdthesis": "{author}, \"{title},\" Ph.D. dissertation, {school}<, {address}>, {year}.",
        "misc": "{author}, \"{title},\"< {howpublished},> <{mon} >{year}.< {note}.>",
    ],
    .chicago: [
        "article": "{author}. {year}. \"{title}.\" {journal}< {volume}>< ({number})><: {pages}>.< https://doi.org/{doi}.>",
        "book": "{author}. {year}. {title}.< {edition}.> <{address}: >{publisher}.",
        "inproceedings": "{author}. {year}. \"{title}.\" In {booktitle}<, edited by {editor}><, {pages}>.< <{address}: >{publisher}.>",
        "techreport": "{author}. {year}. {title}. Technical Report< {number}>. <{address}: >{institution}.",
        "phdthesis": "{author}. {year}. \"{title}.\" PhD diss., {school}.",
        "misc": "{author}. {year}. {title}.< {howpublished}.>< {note}.>",
    ],
    .mla: [
        "article": "{author}. \"{title}.\" {journal}<, vol. {volume}><, no. {number}>, <{mon} >{year}<, {pp}>.< https://doi.org/{doi}.>",
        "book": "{author}. {title}.< {edition},> {publisher}, {year}.",
        "inproceedings": "{author}. \"{title}.\" {booktitle},< edited by {editor},>< {publisher},> {year}<, {pp}>.",
        "techreport": "{author}. {title}. {institution}, {year}.< Technical Report {number}.>",
        "phdthesis": "{author}. {title}. {year}. {school}, PhD dissertation.",
        "misc": "{author}. {title}.< {howpublished},> <{mon} >{year}.< {note}.>",
    ],
]
let templates = templateSources.mapValues { $0.mapValues(parseTemplate) }

enum CitationKind: String {
    case cite, citep, citet, citeauthor, citeyear
    var parenthetical: Bool { self == .cite || self == .citep }
}
struct Citation {
    let start: Int
    let end: Int
    let kind: CitationKind
    let keys: [String]
}
struct AuthorPair: Hashable {
    let a: String
    let b: String
}

func shortName(_ entry: Entry, style: Style, parenthetical: Bool) -> String {
    let names = entry.primary.names.map(\.surname)
    if entry.primary.etAl || names.count >= (style == .chicago ? 4 : 3) { return names[0] + " et al." }
    return listNames(names, conjunction: style == .apa && parenthetical ? "&" : "and", listB: true)
}

final class Formatter {
    private let database: Database
    private var citationRecord: [String] = []
    private var cited: Set<String> = []
    private(set) var output: [String]

    init(database: Database, output: [String]) {
        self.database = database
        self.output = output
    }
    private func ieeeOrder() -> [String] {
        citationRecord + database.byKey.keys.filter { !cited.contains($0) }.sorted()
    }
    private func ieeeNumbers() -> [String: Int] {
        Dictionary(uniqueKeysWithValues: ieeeOrder().enumerated().map { ($0.element, $0.offset + 1) })
    }
    private func reference(_ entry: Entry, style: Style, numbers: [String: Int], repeated: Bool = false) -> String {
        let type = entry.type == "incollection" ? "inproceedings" : entry.type
        let text = renderTemplate(templates[style]![type]!, values: placeholderValues(entry, style: style, repeated: repeated))
        return (style == .ieee ? "[\(numbers[entry.key]!)] " : "") + text
    }
    private func citationText(_ kind: CitationKind, entries: [Entry], style: Style, numbers: [String: Int]) -> String {
        let parenthetical = kind.parenthetical
        func name(_ entry: Entry) -> String { shortName(entry, style: style, parenthetical: parenthetical) }
        if kind == .citeauthor { return entries.map(name).joined(separator: "; ") }
        if kind == .citeyear { return entries.map { $0.yearLabel(style) }.joined(separator: ", ") }
        if style == .mla {
            let text = entries.map(name).joined(separator: "; ")
            return parenthetical ? "(\(text))" : text
        }
        if style == .ieee {
            if !parenthetical { return entries.map { "\(name($0)) [\(numbers[$0.key]!)]" }.joined(separator: "; ") }
            let sorted = entries.map { numbers[$0.key]! }.sorted()
            var pieces: [String] = [], position = 0
            while position < sorted.count {
                var end = position + 1
                while end < sorted.count && sorted[end] == sorted[end - 1] + 1 { end += 1 }
                if end - position >= 3 { pieces.append("[\(sorted[position])]-[\(sorted[end - 1])]") }
                else { pieces.append(contentsOf: sorted[position..<end].map { "[\($0)]" }) }
                position = end
            }
            return pieces.joined(separator: ", ")
        }
        let ordered = parenthetical ? entries.sorted { $0.sortKey.lexicographicallyPrecedes($1.sortKey) } : entries
        var groups: [(name: String, years: [String])] = []
        for entry in ordered {
            let current = name(entry)
            if groups.last?.name != current { groups.append((current, [])) }
            groups[groups.count - 1].years.append(entry.yearLabel(style))
        }
        let text = groups.map { group in
            parenthetical ? group.name + (style == .apa ? ", " : " ") + group.years.joined(separator: ", ")
                : group.name + " (" + group.years.joined(separator: ", ") + ")"
        }.joined(separator: "; ")
        return parenthetical ? "(\(text))" : text
    }
    private func cite(style: Style, text: String) {
        let bytes = Array(text.utf8)
        var citations: [Citation] = [], position = 0
        while position < bytes.count {
            guard let start = bytes[position...].firstIndex(of: 92) else { break }
            let opening = bytes[start...].firstIndex(of: 123)!
            let closing = bytes[opening...].firstIndex(of: 125)!
            let kind = CitationKind(rawValue: ascii(bytes[(start + 1)..<opening]))!
            var seen: Set<String> = []
            let keys = ascii(bytes[(opening + 1)..<closing]).components(separatedBy: ",").filter { seen.insert($0).inserted }
            citations.append(Citation(start: start, end: closing + 1, kind: kind, keys: keys))
            position = closing + 1
        }
        for citation in citations {
            for key in citation.keys where database.byKey[key] == nil {
                output.append("ERROR unknown key '\(key)'")
                return
            }
        }
        for citation in citations {
            for key in citation.keys where cited.insert(key).inserted { citationRecord.append(key) }
        }
        let numbers = ieeeNumbers()
        var result = ""
        position = 0
        for citation in citations {
            let entries = citation.keys.map { database.entries[database.byKey[$0]!] }
            result += ascii(bytes[position..<citation.start])
            result += citationText(citation.kind, entries: entries, style: style, numbers: numbers)
            position = citation.end
        }
        output.append(result + ascii(bytes[position...]))
    }
    private func keygen() {
        let bases = database.entries.map { entry -> String in
            let titleWord = entry.value("title").components(separatedBy: " ").map(letters).first { !$0.isEmpty && !smallWords.contains($0) } ?? ""
            return letters(entry.primary.names[0].last) + ascii(entry.fields["year"]!.utf8.filter(isDigit)) + titleWord
        }
        var counts: [String: Int] = [:], used: [String: Int] = [:]
        for base in bases { counts[base, default: 0] += 1 }
        for (index, base) in bases.enumerated() {
            let suffix = counts[base]! > 1 ? String(UnicodeScalar(97 + used[base, default: 0])!) : ""
            used[base, default: 0] += 1
            output.append("\(database.entries[index].key) -> \(base)\(suffix)")
        }
    }
    private func check() {
        var warnings = 0, firstTitles: [String: String] = [:]
        for entry in database.entries {
            func warn(_ message: String) { output.append("WARN \(entry.key): \(message)"); warnings += 1 }
            let pages = entry.value("pages"), title = entry.value("title")
            if pages.contains("-") && !pages.contains("--") { warn("pages use a single hyphen") }
            let parts = pages.components(separatedBy: "-").filter { !$0.isEmpty }
            if parts.count == 2 && parts.allSatisfy(allDigits) && Int(parts[0])! > Int(parts[1])! { warn("pages are reversed") }
            let year = entry.value("year")
            if year.count != 4 || !allDigits(year) { warn("year is not 4 digits") }
            if !title.utf8.contains(where: { (97...122).contains($0) }) && title.utf8.filter({ (65...90).contains($0) }).count >= 2 { warn("title is all caps") }
            if entry.type == "article" && entry.fields["doi"] == nil { warn("article has no doi") }
            let titleKey = lower(title)
            if let previous = firstTitles[titleKey] { warn("same title as \(previous)") }
            else { firstTitles[titleKey] = entry.key }
            for name in entry.unknownFields { warn("unknown field '\(name)'") }
        }
        output.append("CHECK warnings=\(warnings)")
    }
    private func exportEntry(_ key: String) {
        guard let index = database.byKey[key] else { output.append("ERROR unknown key '\(key)'"); return }
        let entry = database.entries[index]
        output.append("@\(entry.type){\(key),")
        let fields = fieldOrder.filter { entry.fields[$0] != nil } + entry.unknownFields
        for (index, field) in fields.enumerated() {
            output.append("  \(field) = {\(entry.fields[field]!)}" + (index + 1 < fields.count ? "," : ""))
        }
        output.append("}")
    }
    private func stats() {
        var types: [String: Int] = [:], years: [String: Int] = [:], pairs: [AuthorPair: Int] = [:]
        var authors: Set<String> = []
        for entry in database.entries {
            types[entry.type, default: 0] += 1
            years[entry.value("year"), default: 0] += 1
            guard let author = entry.author else { continue }
            let names = Set(author.names.map { $0.format(inverted: false, abbreviated: false) }).sorted()
            authors.formUnion(names)
            for first in names.indices {
                for second in (first + 1)..<names.count {
                    pairs[AuthorPair(a: names[first], b: names[second]), default: 0] += 1
                }
            }
        }
        output.append("ENTRIES \(database.entries.count)")
        for type in types.keys.sorted() { output.append("TYPE \(type) \(types[type]!)") }
        for year in years.keys.sorted() { output.append("YEAR \(year) \(years[year]!)") }
        output.append("AUTHORS \(authors.count)")
        let ranked = pairs.sorted { left, right in
            if left.value != right.value { return left.value > right.value }
            return [left.key.a, left.key.b].lexicographicallyPrecedes([right.key.a, right.key.b])
        }
        if let best = ranked.first { output.append("PAIR \(best.key.a) & \(best.key.b) \(best.value)") }
        else { output.append("PAIR none") }
    }

    func command(_ line: String) {
        let arity = ["FORMAT": -1, "BIBLIOGRAPHY": 1, "CITE": 2, "KEYGEN": 0, "CHECK": 0, "SEARCH": 2, "EXPORT": 1, "STATS": 0]
        let firstSpace = line.firstIndex(of: " ")
        let name = firstSpace.map { String(line[..<$0]) } ?? line
        var parts: [String]
        if (name == "CITE" || name == "SEARCH"), let firstSpace {
            let start = line.index(after: firstSpace)
            if let secondSpace = line[start...].firstIndex(of: " ") {
                parts = [name, String(line[start..<secondSpace]), String(line[line.index(after: secondSpace)...])]
            } else { parts = [name, String(line[start...])] }
        } else { parts = line.components(separatedBy: " ") }
        let args = Array(parts.dropFirst())
        guard let required = arity[name] else { output.append("ERROR unknown command '\(name)'"); return }
        if name == "FORMAT" ? args.count < 2 : args.count != required { output.append("ERROR wrong number of arguments"); return }
        var style = Style.apa
        if ["FORMAT", "BIBLIOGRAPHY", "CITE"].contains(name) {
            guard let parsed = Style(rawValue: args[0]) else { output.append("ERROR unknown style '\(args[0])'"); return }
            style = parsed
        }
        switch name {
        case "FORMAT":
            let numbers = ieeeNumbers()
            for key in args.dropFirst() {
                if let index = database.byKey[key] { output.append(reference(database.entries[index], style: style, numbers: numbers)) }
                else { output.append("ERROR unknown key '\(key)'") }
            }
        case "BIBLIOGRAPHY":
            let numbers = ieeeNumbers()
            let order = style == .ieee ? ieeeOrder().map { database.byKey[$0]! } : database.bibliography
            output.append(style == .mla ? "Works Cited" : "References")
            var previous: NameList?
            for index in order {
                let entry = database.entries[index]
                let repeated = (style == .chicago || style == .mla) && previous == entry.primary
                output.append(reference(entry, style: style, numbers: numbers, repeated: repeated))
                previous = entry.primary
            }
        case "CITE": cite(style: style, text: args[1])
        case "KEYGEN": keygen()
        case "CHECK": check()
        case "EXPORT": exportEntry(args[0])
        case "STATS": stats()
        case "SEARCH":
            let needle = lower(args[1])
            let keys = database.entries.filter { $0.fields[args[0]] != nil && lower($0.value(args[0])).contains(needle) }.map(\.key)
            output.append(keys.isEmpty ? "MATCHES 0" : "MATCHES \(keys.count): " + keys.joined(separator: " "))
        default: break
        }
    }
}

var databaseLines: [String] = []
while let line = readLine(), line != "%%" { databaseLines.append(line) }
var output: [String] = []
let database = Database(lines: databaseLines, output: &output)
let formatter = Formatter(database: database, output: output)
let commandCount = Int(readLine()!)!
for _ in 0..<commandCount { formatter.command(readLine()!) }
print(formatter.output.joined(separator: "\n"))

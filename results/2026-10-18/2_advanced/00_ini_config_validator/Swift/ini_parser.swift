import Foundation

enum StatementKind {
    case assign, append, unset, inherit, include
}

struct Statement {
    let kind: StatementKind
    let line: Int
    let target: String
    var value = ""
}

struct Document {
    let name: String
    var statements: [Statement] = []
    var diagnostics: [Diagnostic] = []
}

func isName(_ text: String) -> Bool {
    let bytes = Array(text.utf8)
    guard let first = bytes.first, first >= 97 && first <= 122 else { return false }
    return bytes.dropFirst().allSatisfy {
        ($0 >= 97 && $0 <= 122) || isDigit($0) || $0 == 95
    }
}

func isSectionName(_ text: String) -> Bool {
    text.components(separatedBy: ".").allSatisfy(isName)
}

private func trimOutside(_ source: [Segment]) -> [Segment] {
    var segments = source
    if !segments[0].quoted {
        segments[0].text = String(segments[0].text.drop(while: { $0 == " " }))
    }
    let last = segments.count - 1
    if !segments[last].quoted {
        segments[last].text = String(segments[last].text.reversed().drop(while: { $0 == " " }).reversed())
    }
    return segments
}

func parseDocument(name: String, text: String) -> Document {
    var document = Document(name: name)
    var section: String?
    var base: String?
    var assigned: [String: Int] = [:]

    func report(_ line: Int, _ code: String, _ message: String) {
        document.diagnostics.append(Diagnostic(origin: Origin(document: name, line: line),
                                               code: code, message: message))
    }

    for line in logicalLines(text) {
        if let error = line.error {
            report(line.number, error.code, error.message)
            continue
        }
        var segments = trimOutside(line.segments)
        let first = segments[0].text
        if segments.count == 1 && first.isEmpty { continue }

        if first.hasPrefix("[") {
            var valid = segments.count == 1 && first.hasSuffix("]") && first.count >= 2
            let inside = valid ? String(first.dropFirst().dropLast()) : ""
            let (headerText, parentText) = partition(inside, at: ":")
            let header = trimSpaces(headerText)
            let parent = parentText.map(trimSpaces)
            let relative = header.hasPrefix(".") && isSectionName(String(header.dropFirst()))
            valid = valid && (parent == nil || isSectionName(parent!)) &&
                    (relative || isSectionName(header))
            if !valid || (relative && base == nil) {
                report(line.number, "E_SECTION", valid ? "relative section without base" : "invalid section header")
                section = nil
            } else {
                if relative { section = base! + header }
                else { section = header; base = header }
                if let parent {
                    document.statements.append(Statement(kind: .inherit, line: line.number,
                                                         target: section!, value: parent))
                }
            }
            continue
        }

        if first.hasPrefix("@") {
            let words = first.split(separator: " ").map(String.init)
            guard segments.count == 1, words.count == 2,
                  words[0] == "@include" || words[0] == "@unset", isName(words[1]) else {
                report(line.number, "E_SYNTAX", "invalid directive")
                continue
            }
            if words[0] == "@include" {
                document.statements.append(Statement(kind: .include, line: line.number, target: words[1]))
            } else if let section {
                document.statements.append(Statement(kind: .unset, line: line.number,
                                                     target: section + "." + words[1]))
            } else {
                report(line.number, "E_NO_SECTION", "no current section")
            }
            continue
        }

        guard segments.contains(where: { !$0.quoted && $0.text.contains("=") }) else {
            report(line.number, "E_SYNTAX", "invalid line")
            continue
        }
        guard let equal = first.firstIndex(of: "=") else {
            report(line.number, "E_SYNTAX", "invalid key")
            continue
        }
        var key = trimSpaces(String(first[..<equal]))
        let append = key.hasSuffix("+")
        if append { key = trimSpaces(String(key.dropLast())) }
        guard isName(key) else {
            report(line.number, "E_SYNTAX", "invalid key")
            continue
        }
        segments[0].text = String(first[first.index(after: equal)...])
        segments = trimOutside(segments)
        let value: String
        if segments.count == 1 {
            value = segments[0].text
        } else if segments.count == 3 && segments[0].text.isEmpty && segments[2].text.isEmpty {
            value = segments[1].text
        } else {
            report(line.number, "E_SYNTAX", "invalid value")
            continue
        }
        guard let section else {
            report(line.number, "E_NO_SECTION", "no current section")
            continue
        }
        let fullKey = section + "." + key
        if !append {
            if let previous = assigned[fullKey] {
                report(line.number, "W_DUPLICATE", "\(fullKey) already set at line \(previous)")
            }
            assigned[fullKey] = line.number
        }
        document.statements.append(Statement(kind: append ? .append : .assign, line: line.number,
                                             target: fullKey, value: value))
    }
    return document
}

import Foundation

enum Kind: String {
    case string, int, bool, size, duration, host, path, url, date, list
    case enumeration = "enum"
}

final class Spec {
    let line: Int
    let pattern: String
    let sectionParts: [String]
    let key: String
    let kind: Kind
    let wildcard: Bool
    var required = false
    var secret = false
    var unique = false
    var fixed = false
    var defaultValue: String?
    var range: (lower: String, upper: String)?
    var values: [String] = []
    var item: Kind = .string
    var aliases: [String] = []
    var when: String?
    var le: String?

    init(line: Int, words: [String]) {
        self.line = line
        pattern = words[0]
        let (section, name) = splitKey(words[0])
        let parts = section.components(separatedBy: ".")
        sectionParts = parts
        key = name
        wildcard = parts.contains("*")
        kind = Kind(rawValue: words[1])!
        for word in words.dropFirst(2) {
            let (attribute, argument) = partition(word, at: "=")
            switch attribute {
            case "required": required = true
            case "secret": secret = true
            case "unique": unique = true
            case "fixed": fixed = true
            case "default": defaultValue = argument!
            case "range":
                let (lower, upper) = partition(argument!, at: "..")
                range = (lower, upper!)
            case "values": values = argument!.components(separatedBy: ",")
            case "item": item = Kind(rawValue: argument!)!
            case "alias": aliases = argument!.components(separatedBy: ",")
            case "when": when = argument!
            case "le": le = argument!
            default: break
            }
        }
    }

    func matches(_ section: String) -> Bool {
        let parts = section.components(separatedBy: ".")
        return parts.count == sectionParts.count && zip(sectionParts, parts).allSatisfy {
            $0.0 == "*" || $0.0 == $0.1
        }
    }
}

struct Schema {
    let specs: [Spec]

    init(path: String) throws {
        let text = try String(contentsOfFile: path, encoding: .ascii)
        specs = fileLines(text).enumerated().compactMap { index, line in
            guard !trimSpaces(line).isEmpty, !line.hasPrefix("#") else { return nil }
            return Spec(line: index + 1, words: line.components(separatedBy: " "))
        }
    }

    func spec(for key: String) -> Spec? {
        if let exact = specs.first(where: { !$0.wildcard && $0.pattern == key }) { return exact }
        let (section, name) = splitKey(key)
        return specs.first { $0.wildcard && $0.key == name && $0.matches(section) }
    }

    func targetKeys(for target: Spec, sections: Set<String>) -> [String] {
        if !target.wildcard { return [target.pattern] }
        return sections.compactMap { section -> String? in
            let key = section + "." + target.key
            return target.matches(section) && spec(for: key) === target ? key : nil
        }.sorted(by: keyLess)
    }
}

import Foundation

struct Diagnostic { let line: Int; let code: String; let message: String }
struct Substitution { let source: String; let replacement: [String]; let line: Int }
struct SynonymGroup { let name: String; let members: Set<String>; let line: Int }
struct Item { let kind: String; let text: String; let arguments: [String]; let line: Int }
struct Rule { let kind: String; let pattern: [String]; let line: Int; var items: [Int] = [] }
struct Keyword { let word: String; let rank: Int; let line: Int; var memories: [Int] = []; var decomps: [Int] = [] }

let textDirectives: Set<String> = ["INITIAL", "FINAL", "DEFAULT", "QUESTION", "REPEAT"]
let globalDirectives = textDirectives.union(["QUIT", "STOP", "MEMSIZE", "PERSIST", "PRE", "POST", "SYNON"])
let ruleDirectives: Set<String> = ["DECOMP", "MEMORY"]
let itemDirectives: Set<String> = ["REASM", "GOTO", "NEWKEY", "RESTATE"]

final class Script {
    let lines: [String]
    var texts = Dictionary(uniqueKeysWithValues: textDirectives.map { ($0, [String]()) })
    var quit: Set<String> = []
    var stop: Set<String> = []
    var capacity = 3
    var persist: Set<String> = []
    var pres: [Substitution] = []
    var posts: [Substitution] = []
    var pre: [String: [String]] = [:]
    var post: [String: [String]] = [:]
    var groups: [SynonymGroup] = []
    var groupWords: [String: Set<String>] = [:]
    var keywords: [Keyword] = []
    var keywordMap: [String: Int] = [:]
    var rules: [Rule] = []
    var items: [Item] = []
    var diagnostics: [Diagnostic] = []
    init(lines: [String]) { self.lines = lines }
}

func isWord(_ text: String) -> Bool {
    let bytes = Array(text.utf8)
    return !bytes.isEmpty && bytes.first != 39 && bytes.last != 39 && bytes.allSatisfy {
        (97...122).contains($0) || (48...57).contains($0) || $0 == 39
    }
}

func isNumber(_ text: String) -> Bool {
    (1...2).contains(text.utf8.count) && text.utf8.allSatisfy { (48...57).contains($0) }
}

func isReference(_ text: String) -> Bool {
    let bytes = Array(text.utf8)
    return bytes.count == 3 && bytes[0] == 40 && (48...57).contains(bytes[1]) && bytes[2] == 41
}

func isElement(_ text: String) -> Bool {
    text == "*" || text == "#" || (text.hasPrefix("@") ? isWord(String(text.dropFirst())) : isWord(text))
}

func wellFormed(_ name: String, _ args: [String]) -> Bool {
    if textDirectives.contains(name) || name == "REASM" { return !args.isEmpty }
    switch name {
    case "QUIT", "STOP": return !args.isEmpty && args.allSatisfy(isWord)
    case "MEMSIZE": return args.count == 1 && isNumber(args[0]) && (1...20).contains(Int(args[0])!)
    case "PERSIST": return args.count == 1 && ["cycles", "memory"].contains(args[0])
    case "PRE", "SYNON": return args.count >= 2 && args.allSatisfy(isWord)
    case "POST": return args.count >= 2 && isWord(args[0])
    case "KEY": return args.count == 2 && isWord(args[0]) && isNumber(args[1])
    case "DECOMP", "MEMORY": return !args.isEmpty && args.allSatisfy(isElement)
    case "GOTO": return args.count == 1 && isWord(args[0])
    case "NEWKEY": return args.isEmpty
    case "RESTATE": return args.count >= 2 && isWord(args[0]) && args.dropFirst().allSatisfy { isWord($0) || isReference($0) }
    default: return false
    }
}

func readLines(_ path: String) throws -> [String] {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    return Array(text.components(separatedBy: "\n").dropLast())
}

func loadScript(_ path: String) throws -> Script {
    let script = Script(lines: try readLines(path))
    var keyword: Int?
    var rule: Int?
    var ignoring = false
    var definitions: [String: Int] = [:]
    for (offset, line) in script.lines.enumerated() {
        if line.isEmpty || line.hasPrefix("#") { continue }
        let number = offset + 1
        let words = line.components(separatedBy: " ")
        let name = words[0]
        let args = Array(words.dropFirst())
        let text = line.firstIndex(of: " ").map { String(line[line.index(after: $0)...]) } ?? ""
        if globalDirectives.contains(name) || name == "KEY" {
            keyword = nil; rule = nil; ignoring = false
        } else if ruleDirectives.contains(name) || itemDirectives.contains(name) {
            if ignoring { continue }
            if ruleDirectives.contains(name) { rule = nil }
        }
        let identity: String?
        if name == "MEMSIZE" { identity = name }
        else if ["KEY", "SYNON", "PRE", "POST", "PERSIST"].contains(name), let first = args.first { identity = "\(name) \(first)" }
        else { identity = nil }
        let problem: (String, String)?
        if !globalDirectives.contains(name) && name != "KEY" && !ruleDirectives.contains(name) && !itemDirectives.contains(name) {
            problem = ("SYNTAX", "unknown directive \(name)")
        } else if !wellFormed(name, args) { problem = ("SYNTAX", "bad arguments for \(name)") }
        else if ruleDirectives.contains(name) && keyword == nil { problem = ("ORPHAN", "\(name) without KEY") }
        else if name == "REASM" && rule == nil { problem = ("ORPHAN", "REASM without DECOMP or MEMORY") }
        else if ["GOTO", "NEWKEY", "RESTATE"].contains(name) && (rule == nil || script.rules[rule!].kind == "MEMORY") { problem = ("ORPHAN", "\(name) without DECOMP") }
        else if let identity, let first = definitions[identity] { problem = ("DUPLICATE", "\(identity) first defined at line \(first)") }
        else { problem = nil }
        if let problem {
            script.diagnostics.append(Diagnostic(line: number, code: problem.0, message: problem.1))
            if name == "KEY" && problem.0 == "DUPLICATE" { ignoring = true }
            continue
        }
        if let identity { definitions[identity] = number }
        if textDirectives.contains(name) { script.texts[name]!.append(text); continue }
        switch name {
        case "QUIT": script.quit.formUnion(args)
        case "STOP": script.stop.formUnion(args)
        case "MEMSIZE": script.capacity = Int(args[0])!
        case "PERSIST": script.persist.insert(args[0])
        case "PRE", "POST":
            let substitution = Substitution(source: args[0], replacement: Array(args.dropFirst()), line: number)
            if name == "PRE" { script.pres.append(substitution); script.pre[args[0]] = substitution.replacement }
            else { script.posts.append(substitution); script.post[args[0]] = substitution.replacement }
        case "SYNON":
            script.groups.append(SynonymGroup(name: args[0], members: Set(args), line: number))
            script.groupWords[args[0]] = Set(args)
        case "KEY":
            keyword = script.keywords.count
            script.keywordMap[args[0]] = keyword!
            script.keywords.append(Keyword(word: args[0], rank: Int(args[1])!, line: number))
        case "DECOMP", "MEMORY":
            rule = script.rules.count
            script.rules.append(Rule(kind: name, pattern: args, line: number))
            if name == "DECOMP" { script.keywords[keyword!].decomps.append(rule!) }
            else { script.keywords[keyword!].memories.append(rule!) }
        default:
            script.rules[rule!].items.append(script.items.count)
            script.items.append(Item(kind: name, text: text, arguments: args, line: number))
        }
    }
    return script
}

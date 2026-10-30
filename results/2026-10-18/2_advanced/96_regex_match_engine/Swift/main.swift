import Foundation
struct Flags {
    let i: Bool, m: Bool, s: Bool
}
typealias Capture = [Int?]
enum Instruction {
    case char(Int), any, characterClass(Set<Int>, Bool), split(Int, Int), jump(Int), save(Int), assertion(String), backref(Int), look(String, Int), match
}
indirect enum Node {
    case literal(Int), any, characterClass(Set<Int>, Bool), assertion(String), backref(Int), named(String), group(Int, Node), look(Bool, Node), concat([Node]), alternate([Node]), repeatNode(Node, Int, Int?, String)
}
struct PatternError: Error {
    let message: String, column: Int
}
struct RegexPattern {
    let name: String, flagsText: String, flags: Flags, text: String, groups: Int, names: [String: Int], root: Node?, code: [Instruction], error: PatternError?, pike: Bool
}
func oneOf(_ text: String, _ c: Int?) -> Bool {
    c.map {
        Array(text.utf8).map(Int.init).contains($0)
    } ?? false
}
final class PatternParser {
    let bytes: [Int];
    var index = 0, groups = 0, names: [String: Int] = [:], references: [(Int, Int?, String)] = []
    init(_ text: String) {
        bytes = text.utf8.map(Int.init)
    };
    var peek: Int? {
        index < bytes.count ? bytes[index] : nil
    }
    func error(_ message: String, _ at: Int) -> PatternError {
        PatternError(message: message, column: at + 1)
    }
    func alternation() throws -> Node {
        var nodes = [try concatenation()];
        while peek == 124 {
            index += 1;
            nodes.append(try concatenation())
        };
        return nodes.count == 1 ? nodes[0] : .alternate(nodes)
    }
    func concatenation() throws -> Node {
        var nodes: [Node] = [];
        while peek != nil && !oneOf("|)", peek) {
            nodes.append(try quantified())
        };
        return nodes.count == 1 ? nodes[0] : .concat(nodes)
    }
    func quantified() throws -> Node {
        if oneOf("*+?{", peek) {
            throw error("nothing to repeat", index)
        };
        let node = try element()
        if !oneOf("*+?{", peek) {
            return node
        }
        switch node {
            case .assertion, .look: throw error("nothing to repeat", index);
            default: break
        }
        let minimum: Int, maximum: Int?
        if peek == 123 {
            (minimum, maximum) = try braces()
        }
        else {
            let c = peek!;
            index += 1;
            minimum = c == 43 ? 1 : 0;
            maximum = c == 63 ? 1 : nil
        }
        let kind: String
        if peek == 63 {
            index += 1;
            kind = "lazy"
        } else if peek == 43 {
            index += 1;
            kind = "possessive"
        } else {
            kind = "greedy"
        }
        if oneOf("*+?{", peek) {
            throw error("nested quantifier", index)
        };
        return .repeatNode(node, minimum, maximum, kind)
    }
    func digits() -> Int? {
        let start = index;
        while peek.map(Charset.digit) ?? false {
            index += 1
        };
        return start == index ? nil : Int(String(bytes[start..<index].map {
            Character(UnicodeScalar($0)!)
        }))!
    }
    func braces() throws -> (Int, Int?) {
        let start = index;
        index += 1;
        guard let minimum = digits() else {
            throw error("invalid quantifier", start)
        };
        let maximum: Int?
        if peek == 125 {
            maximum = minimum
        }
        else if peek == 44 {
            index += 1;
            if peek == 125 {
                maximum = nil
            } else {
                guard let value = digits() else {
                    throw error("invalid quantifier", start)
                };
                maximum = value
            }
        }
        else {
            throw error("invalid quantifier", start)
        }
        if peek != 125 {
            throw error("invalid quantifier", start)
        };
        index += 1
        if minimum > 100 || maximum.map({
            $0 > 100
        }) ?? false {
            throw error("quantifier too large", start)
        }
        if maximum.map({
            minimum > $0
        }) ?? false {
            throw error("quantifier range out of order", start)
        };
        return (minimum, maximum)
    }
    func name() throws -> String {
        let start = index
        if peek.map({
            Charset.letter($0) || $0 == 95
        }) ?? false {
            index += 1;
            while peek.map(Charset.word) ?? false {
                index += 1
            }
        }
        if index == start || peek != 62 {
            throw error("invalid group name", index)
        }
        let name = String(bytes[start..<index].map {
            Character(UnicodeScalar($0)!)
        });
        index += 1;
        return name
    }
    func group() throws -> Node {
        let start = index;
        index += 1;
        var mode = "capture", named: String?
        if peek == 63 {
            index += 1
            switch peek {
                case 58: mode = "plain";
                case 61: mode = "ahead";
                case 33: mode = "negative";
                case 60: mode = "capture";
                default: throw error("invalid group", start)
            }
            let namedGroup = peek == 60;
            index += 1
            if namedGroup {
                let nameStart = index, name = try self.name();
                if names[name] != nil {
                    throw error("duplicate group name", nameStart)
                };
                named = name
            }
        }
        var group: Int?
        if mode == "capture" {
            groups += 1;
            group = groups;
            if let named {
                names[named] = groups
            }
        }
        let content = try alternation();
        if peek != 41 {
            throw error("missing )", start)
        };
        index += 1
        if let group {
            return .group(group, content)
        };
        return mode == "plain" ? content : .look(mode == "ahead", content)
    }
    func classItem() throws -> (Set<Int>, Bool) {
        let start = index;
        guard let c = peek else {
            throw error("missing ]", start)
        };
        index += 1
        if c != 92 {
            return ([c], false)
        };
        guard let escaped = peek else {
            throw error("trailing backslash", start)
        };
        index += 1
        if oneOf("dDwWsS", escaped) {
            return (Charset.base(escaped), true)
        }
        if escaped == 110 {
            return ([10], false)
        };
        if escaped == 116 {
            return ([9], false)
        }
        if Charset.letter(escaped) || Charset.digit(escaped) {
            throw error("invalid escape", start)
        };
        return ([escaped], false)
    }
    func characterClass() throws -> Node {
        let start = index;
        index += 1;
        let negated = peek == 94;
        if negated {
            index += 1
        };
        if peek == 93 {
            throw error("empty class", index)
        };
        var set: Set<Int> = []
        while true {
            guard peek != nil else {
                throw error("missing ]", start)
            };
            if peek == 93 {
                index += 1;
                break
            }
            let (left, leftSet) = try classItem()
            if peek == 45 && index + 1 < bytes.count && bytes[index + 1] != 93 {
                let hyphen = index;
                index += 1;
                if leftSet {
                    throw error("invalid range", hyphen)
                };
                let (right, rightSet) = try classItem(), a = left.first!, b = right.first!
                if rightSet || a > b {
                    throw error("invalid range", hyphen)
                };
                set.formUnion(a...b)
            } else {
                set.formUnion(left)
            }
        };
        return .characterClass(set, negated)
    }
    func escape() throws -> Node {
        let start = index;
        index += 1;
        guard let c = peek else {
            throw error("trailing backslash", start)
        };
        index += 1
        if oneOf("dDwWsS", c) {
            return .characterClass(Charset.base((65...90).contains(c) ? c + 32 : c), (65...90).contains(c))
        }
        switch c {
            case 98: return .assertion("WORD")
            case 66: return .assertion("NOTWORD")
            case 110: return .literal(10)
            case 116: return .literal(9)
            case 49...57: index -= 1;
            let number = digits()!;
            references.append((start, number, ""));
            return .backref(number)
            case 107: if peek != 60 {
                throw error("invalid escape", start)
            };
            index += 1;
            let name = try self.name();
            references.append((start, nil, name));
            return .named(name)
            default: if Charset.letter(c) || Charset.digit(c) {
                throw error("invalid escape", start)
            };
            return .literal(c)
        }
    }
    func element() throws -> Node {
        switch peek! {
            case 40: return try group();
            case 91: return try characterClass();
            case 92: return try escape();
            case 46: index += 1;
            return .any;
            case 94: index += 1;
            return .assertion("BOL");
            case 36: index += 1;
            return .assertion("EOL");
            case let c: index += 1;
            return .literal(c)
        }
    }
    func parse() throws -> Node {
        let root = try alternation();
        if index < bytes.count {
            throw error("unmatched )", index)
        }
        for (column, number, name) in references {
            if let number {
                if number > groups {
                    throw error("invalid group reference", column)
                }
            } else if names[name] == nil {
                throw error("unknown group name", column)
            }
        };
        return root
    }
}
func compile(_ node: Node, _ code: inout [Instruction], _ names: [String: Int]) {
    switch node {
        case .literal(let c): code.append(.char(c))
        case .any: code.append(.any)
        case .characterClass(let s, let n): code.append(.characterClass(s, n))
        case .assertion(let kind): code.append(.assertion(kind))
        case .backref(let k): code.append(.backref(k))
        case .named(let name): code.append(.backref(names[name]!))
        case .group(let k, let content): code.append(.save(2 * k));
        compile(content, &code, names);
        code.append(.save(2 * k + 1))
        case .look(let positive, let content): let start = code.count, kind = positive ? "AHEAD" : "NOT";
        code.append(.look(kind, 0));
        compile(content, &code, names);
        code.append(.match);
        code[start] = .look(kind, code.count)
        case .concat(let nodes): for node in nodes {
            compile(node, &code, names)
        }
        case .alternate(let nodes):
        var jumps: [Int] = []
        for node in nodes.dropLast() {
            let split = code.count;
            code.append(.split(split + 1, 0));
            compile(node, &code, names);
            jumps.append(code.count);
            code.append(.jump(0));
            code[split] = .split(split + 1, code.count)
        }
        compile(nodes.last!, &code, names);
        let end = code.count;
        for jump in jumps {
            code[jump] = .jump(end)
        }
        case .repeatNode(let content, let minimum, let maximum, let kind):
        if kind == "possessive" {
            let start = code.count;
            code.append(.look("ATOMIC", 0));
            compile(.repeatNode(content, minimum, maximum, "greedy"), &code, names);
            code.append(.match);
            code[start] = .look("ATOMIC", code.count);
            return
        }
        let greedy = kind == "greedy"
        if let maximum {
            for _ in 0..<minimum {
                compile(content, &code, names)
            };
            var splits: [Int] = []
            for _ in minimum..<maximum {
                splits.append(code.count);
                code.append(.split(0, 0));
                compile(content, &code, names)
            }
            let end = code.count;
            for split in splits {
                code[split] = greedy ? .split(split + 1, end) : .split(end, split + 1)
            }
        } else if minimum == 0 {
            let split = code.count;
            code.append(.split(0, 0));
            compile(content, &code, names);
            code.append(.jump(split));
            code[split] = greedy ? .split(split + 1, code.count) : .split(code.count, split + 1)
        } else {
            for _ in 0..<(minimum - 1) {
                compile(content, &code, names)
            };
            let start = code.count;
            compile(content, &code, names);
            let end = code.count + 1;
            code.append(greedy ? .split(start, end) : .split(end, start))
        }
    }
}
func length(_ node: Node) -> (Int, Int?) {
    switch node {
        case .literal, .any, .characterClass: return (1, 1)
        case .assertion, .look: return (0, 0)
        case .backref, .named: return (0, nil)
        case .group(_, let content): return length(content)
        case .concat(let nodes): let ranges = nodes.map(length);
        return (ranges.reduce(0) {
            $0 + $1.0
        }, ranges.contains {
            $0.1 == nil
        } ? nil : ranges.reduce(0) {
            $0 + $1.1!
        })
        case .alternate(let nodes): let ranges = nodes.map(length);
        return (ranges.map {
            $0.0
        }.min()!, ranges.contains {
            $0.1 == nil
        } ? nil : ranges.map {
            $0.1!
        }.max()!)
        case .repeatNode(let content, let minimum, let maximum, _): let (a, b) = length(content);
        return (a * minimum, b == 0 ? 0 : b.flatMap {
            b in maximum.map {
                b * $0
            }
        })
    }
}
func first(_ node: Node, _ flags: Flags) -> (Set<Int>, Bool) {
    switch node {
        case .literal(let c): return (flags.i && Charset.letter(c) ? [c, Charset.swap(c)] : [c], false)
        case .any: return (Set((0..<128).filter {
            flags.s || $0 != 10
        }), false)
        case .characterClass(let s, let n): return (Set((0..<128).filter {
            Charset.classMatches($0, s, n, flags)
        }), false)
        case .assertion, .look: return ([], true)
        case .backref, .named: return (Set(0..<128), true)
        case .group(_, let content): return first(content, flags)
        case .concat(let nodes): var set: Set<Int> = [];
        for node in nodes {
            let (part, nullable) = first(node, flags);
            set.formUnion(part);
            if !nullable {
                return (set, false)
            }
        };
        return (set, true)
        case .alternate(let nodes): var set: Set<Int> = [], nullable = false;
        for node in nodes {
            let (part, empty) = first(node, flags);
            set.formUnion(part);
            nullable = nullable || empty
        };
        return (set, nullable)
        case .repeatNode(let content, let minimum, let maximum, _): if maximum == 0 {
            return ([], true)
        };
        let (set, nullable) = first(content, flags);
        return (set, nullable || minimum == 0)
    }
}
func consumes(_ instruction: Instruction, _ subject: [Int], _ q: Int, _ flags: Flags) -> Bool {
    if q == subject.count {
        return false
    }
    switch instruction {
        case .char(let c): return Charset.equal(c, subject[q], flags);
        case .any: return flags.s || subject[q] != 10;
        case .characterClass(let set, let negated): return Charset.classMatches(subject[q], set, negated, flags);
        default: return false
    }
}
func readPattern(_ line: String) -> RegexPattern {
    let f = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false).map(String.init), parser = PatternParser(f[2]), flags = Flags(i: f[1].contains("i"), m: f[1].contains("m"), s: f[1].contains("s"))
    var root: Node?, error: PatternError?, code: [Instruction] = []
    do {
        root = try parser.parse();
        code.append(.save(0));
        compile(root!, &code, parser.names);
        code += [.save(1), .match]
    } catch let failure as PatternError {
        error = failure
    } catch {
        preconditionFailure()
    }
    let pike = !code.contains {
        switch $0 {
            case .backref, .look: return true;
            default: return false
        }
    }
    return RegexPattern(name: f[0], flagsText: f[1], flags: flags, text: f[2], groups: parser.groups, names: parser.names, root: root, code: code, error: error, pike: pike)
}
func decode(_ quoted: String) -> [Int] {
    let bytes = quoted.utf8.map(Int.init);
    var result: [Int] = [], i = 1
    while i + 1 < bytes.count {
        if bytes[i] == 92 {
            i += 1;
            result.append(bytes[i] == 110 ? 10 : bytes[i] == 116 ? 9 : bytes[i])
        } else {
            result.append(bytes[i])
        };
        i += 1
    };
    return result
}
enum TemplatePart {
    case character(Int), group(Int)
}
func template(_ bytes: [Int], _ pattern: RegexPattern) -> [TemplatePart]? {
    var parts: [TemplatePart] = [], i = 0
    while i < bytes.count {
        if bytes[i] != 36 {
            parts.append(.character(bytes[i]));
            i += 1;
            continue
        };
        i += 1
        if i < bytes.count && bytes[i] == 36 {
            parts.append(.character(36));
            i += 1;
            continue
        }
        let number: Int
        if i < bytes.count && Charset.digit(bytes[i]) {
            number = bytes[i] - 48;
            i += 1
        }
        else if i < bytes.count && bytes[i] == 123 {
            i += 1;
            guard let end = (i..<bytes.count).first(where: {
                bytes[$0] == 125
            }) else {
                return nil
            };
            let name = String(bytes[i..<end].map {
                Character(UnicodeScalar($0)!)
            });
            i = end + 1
            if !name.isEmpty && name.utf8.allSatisfy({
                (48...57).contains($0)
            }) {
                number = Int(name)!
            } else {
                guard let group = pattern.names[name] else {
                    return nil
                };
                number = group
            }
        } else {
            return nil
        }
        if number > pattern.groups {
            return nil
        };
        parts.append(.group(number))
    };
    return parts
}
func group(_ capture: Capture, _ k: Int, _ subject: [Int]) -> [Int]? {
    guard let a = capture[2 * k], let b = capture[2 * k + 1] else {
        return nil
    };
    return Array(subject[a..<b])
}
func matchLines(_ capture: Capture, _ pattern: RegexPattern, _ subject: [Int]) -> [String] {
    (0...pattern.groups).map {
        k in let heading = k == 0 ? "match" : "group \(k)";
        if let value = group(capture, k, subject) {
            return "\(heading) \(capture[2 * k]!)-\(capture[2 * k + 1]!) \(Formatter.quote(value))"
        };
        return heading + " -"
    }
}
func scanBacktrack(_ vm: Backtrack, _ length: Int, _ scan: Bool) throws -> [Capture] {
    var matches: [Capture] = [], start = 0
    while start <= length {
        guard let capture = try vm.search(start) else {
            break
        };
        start = capture[1]! + (capture[0] == capture[1] ? 1 : 0);
        matches.append(capture);
        if !scan {
            break
        }
    };
    return matches
}
func scanPike(_ vm: Pike, _ length: Int, _ scan: Bool) -> [Capture] {
    var matches: [Capture] = [], start = 0
    while start <= length {
        guard let capture = vm.search(start) else {
            break
        };
        start = capture[1]! + (capture[0] == capture[1] ? 1 : 0);
        matches.append(capture);
        if !scan {
            break
        }
    };
    return matches
}
func list(_ pattern: RegexPattern) -> [String] {
    let names = pattern.names.sorted {
        $0.value < $1.value
    }.map {
        "\($0.key):\($0.value)"
    }, (minimum, maximum) = length(pattern.root!), (set, _) = first(pattern.root!, pattern.flags)
    var lines = ["=== " + pattern.name, "flags=\(pattern.flagsText) groups=\(pattern.groups) names=\(names.isEmpty ? "-" : names.joined(separator: ",")) length=\(minimum)..\(maximum.map(String.init) ?? "inf") first=\(set.isEmpty ? "-" : Formatter.set(set)) pike=\(pattern.pike ? "yes" : "no") size=\(pattern.code.count)"]
    lines += pattern.code.enumerated().map {
        "\($0.offset) \(Formatter.instruction($0.element))"
    };
    return lines
}
func readLines(_ name: String) -> [String] {
    try! String(contentsOfFile: "input/" + name, encoding: .ascii).split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
}
func write(_ name: String, _ lines: [String]) {
    try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try! (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: true, encoding: .utf8)
}
let patterns = readLines("patterns.txt").map(readPattern), byName = Dictionary(uniqueKeysWithValues: patterns.enumerated().map {
    ($0.element.name, $0.offset)
})
var subjects: [String: [Int]] = [:], errors: [String] = [], results: [String] = [], programs: [String] = [], steps = ["command,engine,steps"]
for line in readLines("subjects.txt") {
    let f = line.split(separator: " ", maxSplits: 1).map(String.init);
    subjects[f[0]] = decode(f[1])
}
for pattern in patterns {
    if let error = pattern.error {
        errors += ["\(pattern.name): \(error.message) at column \(error.column)", "  " + pattern.text, String(repeating: " ", count: error.column + 1) + "^"]
    }
}
if errors.isEmpty {
    errors = ["no errors"]
}
for (index, line) in readLines("commands.txt").enumerated() {
    results.append("#\(index + 1) \(line)")
    let f = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: false).map(String.init), command = f[0], replacing = command == "REPLACE", pattern = patterns[byName[f[replacing ? 2 : 1]]!]
    if pattern.error != nil {
        results.append("invalid pattern");
        continue
    }
    if command == "LIST" {
        results.append("instructions \(pattern.code.count)");
        programs += list(pattern);
        continue
    }
    let subject = subjects[f[replacing ? 3 : 2]]!, parts: [TemplatePart]
    if replacing {
        guard let parsed = template(decode(f[4]), pattern) else {
            results.append("invalid template");
            continue
        };
        parts = parsed
    } else {
        parts = []
    }
    let scan = ["FINDALL", "SPLIT"].contains(command) || replacing && f[1] == "ALL", full = command == "MATCH", backtrack = Backtrack(pattern.code, subject, pattern.flags, pattern.groups, full)
    let backtrackMatches = try? scanBacktrack(backtrack, subject.count, scan)
    steps.append("\(index + 1),backtrack,\(backtrack.steps)")
    let matches: [Capture], label: String
    if pattern.pike {
        let pike = Pike(pattern.code, subject, pattern.flags, pattern.groups, full), found = scanPike(pike, subject.count, scan);
        steps.append("\(index + 1),pike,\(pike.steps)")
        if let backtrackMatches {
            if backtrackMatches != found {
                results.append("MISMATCH");
                continue
            };
            matches = found;
            label = "both"
        }
        else {
            matches = found;
            label = "pike (backtrack: TOO_MANY_STEPS)"
        }
    } else {
        guard let backtrackMatches else {
            results.append("TOO_MANY_STEPS");
            continue
        };
        matches = backtrackMatches;
        label = "backtrack"
    }
    results.append("engine " + label)
    if command == "MATCH" || command == "SEARCH" {
        if let capture = matches.first {
            results += matchLines(capture, pattern, subject)
        } else {
            results.append("no match")
        }
    }
    else if command == "FINDALL" {
        results.append("matches \(matches.count)");
        for capture in matches {
            results += matchLines(capture, pattern, subject)
        }
    }
    else if replacing {
        var result: [Int] = [], last = 0
        for capture in matches {
            result += subject[last..<capture[0]!]
            for part in parts {
                switch part {
                    case .character(let c): result.append(c);
                    case .group(let k): result += group(capture, k, subject) ?? []
                }
            };
            last = capture[1]!
        };
        result += subject.dropFirst(last);
        results += ["replacements \(matches.count)", "result " + Formatter.quote(result)]
    } else {
        results += ["pieces \(matches.count + 1)", "piece " + Formatter.quote(Array(subject.prefix(matches.first?[0] ?? subject.count)))]
        for (i, capture) in matches.enumerated() {
            if pattern.groups > 0 {
                for k in 1...pattern.groups {
                    results.append("group \(k) " + (group(capture, k, subject).map(Formatter.quote) ?? "-"))
                }
            }
            let end = i + 1 < matches.count ? matches[i + 1][0]! : subject.count;
            results.append("piece " + Formatter.quote(Array(subject[capture[1]!..<end])))
        }
    }
}
if programs.isEmpty {
    programs = ["no programs"]
}
write("results.txt", results);
write("programs.txt", programs);
write("steps.csv", steps);
write("errors.txt", errors)

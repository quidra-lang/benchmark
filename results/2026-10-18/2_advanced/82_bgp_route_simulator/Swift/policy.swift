struct Community: Hashable, Comparable {
    let x: Int, y: Int
    init(_ text: String) { if text == "NO_EXPORT" { x = 65535; y = 65281 } else { let parts = text.split(separator: ":"); x = Int(parts[0])!; y = Int(parts[1])! } }
    var text: String { x == 65535 && y == 65281 ? "NO_EXPORT" : "\(x):\(y)" }
    static func < (a: Self, b: Self) -> Bool { a.x == b.x ? a.y < b.y : a.x < b.x }
    static func text(_ communities: Set<Self>) -> String { communities.isEmpty ? "-" : communities.sorted().map(\.text).joined(separator: ",") }
}
enum Condition { case prefix(String), contains(Int), origin(Int), length(Int, Int), community(Community) }
enum Action { case deny, allow, local(Int), med(Int), prepend(Int), add(Community), remove(Community) }
final class Rule {
    let name: String, owner: Int, importing: Bool, target: String
    var on: Bool, conditions: [Condition] = [], actions: [Action] = [], hits = 0
    init(_ w: [String]) {
        name = w[1]; on = w[2] == "ON"; owner = Int(w[3])!; importing = w[4] == "IMPORT"; target = w[5]
        var i = 6
        while w[i] != "THEN" {
            switch w[i] { case "PREFIX": conditions.append(.prefix(w[i + 1])); case "CONTAINS": conditions.append(.contains(Int(w[i + 1])!)); case "ORIGINAS": conditions.append(.origin(Int(w[i + 1])!)); case "LENGTH": let range = w[i + 1].split(separator: "-").map { Int($0)! }; conditions.append(.length(range[0], range[1])); default: conditions.append(.community(Community(w[i + 1]))) }; i += 2
        }
        i += 1
        while i < w.count {
            switch w[i] {
            case "DENY": actions.append(.deny); i += 1
            case "ALLOW": actions.append(.allow); i += 1
            case "LOCALPREF": actions.append(.local(Int(w[i + 1])!)); i += 2
            case "MED": actions.append(.med(Int(w[i + 1])!)); i += 2
            case "PREPEND": actions.append(.prepend(Int(w[i + 1])!)); i += 2
            case "ADD": actions.append(.add(Community(w[i + 1]))); i += 2
            default: actions.append(.remove(Community(w[i + 1]))); i += 2
            }
        }
    }
}
struct PrefixEntry { let permit: Bool, prefix: Prefix, low: Int, high: Int }
final class Policy {
    var lists: [String: [PrefixEntry]] = [:], rules: [Rule] = []
    init() {
        for w in words("policies.txt") {
            if w[0] == "RULE" { rules.append(Rule(w)); continue }
            let prefix = Prefix(w[3]); var low = prefix.length, high = prefix.length, i = 4
            while i < w.count { if w[i] == "GE" { low = Int(w[i + 1])!; high = 32 } else { high = Int(w[i + 1])! }; i += 2 }
            lists[w[1], default: []].append(PrefixEntry(permit: w[2] == "PERMIT", prefix: prefix, low: low, high: high))
        }
    }
    func permitted(_ name: String, _ prefix: Prefix) -> Bool { lists[name]!.first { $0.low <= prefix.length && prefix.length <= $0.high && $0.prefix.contains(prefix.address) }?.permit ?? false }
    func applied(_ importing: Bool, _ x: Int, _ link: Link, _ prefix: Prefix, _ path: [Int], _ communities: Set<Community>) -> Int? {
        rules.firstIndex { rule in
            rule.on && rule.owner == x && rule.importing == importing && ["*", link.name, String(link.other(x))].contains(rule.target) && rule.conditions.allSatisfy { condition in
                switch condition { case .prefix(let name): return permitted(name, prefix); case .contains(let a): return path.contains(a); case .origin(let a): return (path.last ?? x) == a; case .length(let low, let high): return low <= path.count && path.count <= high; case .community(let c): return communities.contains(c) }
            }
        }
    }
    func edit(_ index: Int, _ communities: Set<Community>) -> Set<Community> { var result = communities; for action in rules[index].actions { switch action { case .add(let c): result.insert(c); case .remove(let c): result.remove(c); default: break } }; return result }
}

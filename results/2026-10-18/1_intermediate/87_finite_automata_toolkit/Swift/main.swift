import Foundation

struct Problem: Error {
    let reason: String
}
func fail(_ reason: String) throws -> Never {
    throw Problem(reason: reason)
}
func displayWord(_ word: String) -> String {
    word.isEmpty ? "e" : word
}
struct Transition: Hashable {
    let from: Int
    let symbol: Character
    let to: Int
}
struct EdgeKey: Hashable {
    let from: Int
    let symbol: Character
}
struct Pair: Hashable {
    let p: Int
    let q: Int
}
final class Automaton {
    let dfa: Bool
    let states: [String]
    let alphabet: [Character]
    let start: Int
    let accepting: Set<Int>
    let transitions: Set<Transition>
    let adjacency: [EdgeKey: Set<Int>]
    init(_ dfa: Bool, _ states: [String], _ alphabet: [Character], _ start: Int, _ accepting: Set<Int>, _ transitions: Set<Transition>) {
        self.dfa = dfa
        self.states = states
        self.alphabet = alphabet
        self.start = start
        self.accepting = accepting
        self.transitions = transitions
        var adjacency = [EdgeKey: Set<Int>]()
        for t in transitions {
            adjacency[EdgeKey(from: t.from, symbol: t.symbol), default: []].insert(t.to)
        }
        self.adjacency = adjacency
    }
    func direct(_ p: Int, _ c: Character) -> Set<Int> {
        adjacency[EdgeKey(from: p, symbol: c)] ?? []
    }
    func delta(_ p: Int, _ c: Character) -> Int {
        direct(p, c).first!
    }
    func summary(_ name: String) -> String {
        "\(dfa ? "DFA" : "NFA") \(name): alphabet=\(String(alphabet)) states=\(states.count) accepting=\(accepting.count) transitions=\(transitions.count)"
    }
    func closure(_ set: Set<Int>) -> Set<Int> {
        var result = set
        var queue = Array(set)
        var at = 0
        while at < queue.count {
            let p = queue[at]
            at += 1
            for q in direct(p, "e") {
                if result.insert(q).inserted {
                    queue.append(q)
                }
            }
        }
        return result
    }
    func initial() -> Set<Int> {
        closure([start])
    }
    func destination(_ set: Set<Int>, _ c: Character) -> Set<Int> {
        closure(Set(set.flatMap {
            direct($0, c)
        }))
    }
    func accepted(_ set: Set<Int>) -> Bool {
        !set.isDisjoint(with: accepting)
    }
    func setText(_ set: Set<Int>) -> String {
        "{" + set.sorted().map {
            states[$0]
        }.joined(separator: ",") + "}"
    }
    func listText(_ set: Set<Int>) -> String {
        set.isEmpty ? "none" : set.sorted().map {
            states[$0]
        }.joined(separator: ",")
    }
    func determinize() -> (Automaton, [String]) {
        var sets = [initial()]
        var index = [sets[0]: 0]
        var transitions = Set<Transition>()
        var i = 0
        while i < sets.count {
            for c in alphabet {
                let next = destination(sets[i], c)
                let j: Int
                if let old = index[next] {
                    j = old
                } else {
                    j = sets.count
                    index[next] = j
                    sets.append(next)
                }
                transitions.insert(Transition(from: i, symbol: c, to: j))
            }
            i += 1
        }
        let result = generated(true, "D", sets.count, alphabet, 0, Set(sets.indices.filter {
            accepted(sets[$0])
        }),
        transitions)
        return (result, sets.indices.map {
            "  D\($0) = \(setText(sets[$0]))"
        })
    }
    func reachable(_ reverse: Bool) -> Set<Int> {
        var result = reverse ? accepting : [start]
        var queue = Array(result)
        var at = 0
        while at < queue.count {
            let s = queue[at]
            at += 1
            for t in transitions where (reverse ? t.to : t.from) == s {
                let next = reverse ? t.from : t.to
                if result.insert(next).inserted {
                    queue.append(next)
                }
            }
        }
        return result
    }
    func minimize() -> (Automaton, [String]) {
        let reachable = reachable(false)
        var details = ["  unreachable: \(listText(Set(states.indices.filter { !reachable.contains($0) })))"]
        var blocks = [true, false].map {
            accept in Set(reachable.filter {
                accepting.contains($0) == accept
            })
        }.filter {
            !$0.isEmpty
        }.sorted {
            $0.min()! < $1.min()!
        }
        func partition(_ blocks: [Set<Int>]) -> String {
            blocks.map(setText).joined(separator: " ")
        }
        details.append("  round 0: \(partition(blocks))")
        var round = 1
        while true {
            var group = Array(repeating: 0, count: states.count)
            for (i, b) in blocks.enumerated() {
                for s in b {
                    group[s] = i
                }
            }
            var split = [[Int]: Set<Int>]()
            for s in reachable {
                let key = [group[s]] + alphabet.map {
                    group[delta(s, $0)]
                }
                split[key, default: []].insert(s)
            }
            let next = split.values.sorted {
                $0.min()! < $1.min()!
            }
            if next.count == blocks.count {
                break
            }
            blocks = next
            details.append("  round \(round): \(partition(blocks))")
            round += 1
        }
        var group = Array(repeating: 0, count: states.count)
        for (i, b) in blocks.enumerated() {
            for s in b {
                group[s] = i
            }
        }
        var sequence = [group[start]]
        var names = [sequence[0]: 0]
        var transitions = Set<Transition>()
        var i = 0
        while i < sequence.count {
            let s = blocks[sequence[i]].min()!
            for c in alphabet {
                let b = group[delta(s, c)]
                let j: Int
                if let old = names[b] {
                    j = old
                } else {
                    j = sequence.count
                    names[b] = j
                    sequence.append(b)
                }
                transitions.insert(Transition(from: i, symbol: c, to: j))
            }
            i += 1
        }
        let accepting = Set(sequence.indices.filter {
            accepted(blocks[sequence[$0]])
        })
        for i in sequence.indices {
            details.append("  M\(i) = \(setText(blocks[sequence[i]]))")
        }
        return (generated(true, "M", sequence.count, alphabet, 0, accepting, transitions), details)
    }
    func product(_ other: Automaton, _ command: String) -> (Automaton, [String]) {
        var pairs = [Pair(p: start, q: other.start)]
        var index = [pairs[0]: 0]
        var transitions = Set<Transition>()
        var i = 0
        while i < pairs.count {
            for c in alphabet {
                let pair = Pair(p: delta(pairs[i].p, c), q: other.delta(pairs[i].q, c))
                let j: Int
                if let old = index[pair] {
                    j = old
                } else {
                    j = pairs.count
                    index[pair] = j
                    pairs.append(pair)
                }
                transitions.insert(Transition(from: i, symbol: c, to: j))
            }
            i += 1
        }
        let accepting = Set(pairs.indices.filter {
            i in
            let a = self.accepting.contains(pairs[i].p)
            let b = other.accepting.contains(pairs[i].q)
            return command == "UNION" ? a || b : command == "INTERSECT" ? a && b : a && !b
        })
        return (generated(true, "P", pairs.count, alphabet, 0, accepting, transitions), pairs.indices.map {
            "  P\($0) = (\(states[pairs[$0].p]),\(other.states[pairs[$0].q]))"
        })
    }
    func smallest() -> String? {
        var seen: Set<Int> = [start]
        var queue = [(start, "")]
        var at = 0
        while at < queue.count {
            let (s, word) = queue[at]
            at += 1
            if accepting.contains(s) {
                return word
            }
            for c in alphabet {
                let q = delta(s, c)
                if seen.insert(q).inserted {
                    queue.append((q, word + String(c)))
                }
            }
        }
        return nil
    }
    func language(_ counting: Bool = true) -> Int? {
        let live = reachable(true)
        var color = Array(repeating: 0, count: states.count)
        var counts = Array(repeating: 0, count: states.count)

        func visit(_ s: Int) -> Int? {
            if !live.contains(s) {
                return 0
            }
            if color[s] == 1 {
                return nil
            }
            if color[s] == 2 {
                return counts[s]
            }
            color[s] = 1
            var count = accepting.contains(s) ? 1 : 0
            for c in alphabet {
                guard let n = visit(delta(s, c)) else {
                    return nil
                }
                if counting {
                    count += n
                }
            }
            color[s] = 2
            counts[s] = counting ? count : 1
            return counts[s]
        }
        return visit(start)
    }
    func count(_ n: Int) -> Int {
        var counts = Array(repeating: 0, count: states.count)
        counts[start] = 1
        for _ in 0..<n {
            var next = Array(repeating: 0, count: states.count)
            for s in states.indices {
                for c in alphabet {
                    next[delta(s, c)] += counts[s]
                }
            }
            counts = next
        }
        return accepting.reduce(0) {
            $0 + counts[$1]
        }
    }
    func enumerate(_ limit: Int) -> String {
        var queue = [(start, "")]
        var at = 0
        var count = 0
        var first = [String]()
        while at < queue.count {
            let (s, word) = queue[at]
            at += 1
            if accepting.contains(s) {
                count += 1
                if first.count < 50 {
                    first.append(displayWord(word))
                }
            }
            if word.count < limit {
                for c in alphabet {
                    queue.append((delta(s, c), word + String(c)))
                }
            }
        }
        return String(count) + (first.isEmpty ? "" : " " + first.joined(separator: " ")) + (count > 50 ? " ..." : "")
    }
    func synchronize() -> String {
        let initial = Set(states.indices)
        var seen: Set<Set<Int>> = [initial]
        var queue = [(initial, "")]
        var at = 0
        while at < queue.count {
            let (set, word) = queue[at]
            at += 1
            if set.count == 1 {
                return "SYNCHRONIZING \(displayWord(word)) -> \(states[set.first!])"
            }
            for c in alphabet {
                let next = Set(set.map {
                    delta($0, c)
                })
                if seen.insert(next).inserted {
                    queue.append((next, word + String(c)))
                }
            }
        }
        return "NOT SYNCHRONIZING"
    }
    func table() -> [String] {
        let symbols = alphabet + (!dfa && transitions.contains {
            $0.symbol == "e"
        } ? [Character("e")] : [])
        var rows = [[""] + symbols.map(String.init)]
        for p in states.indices {
            let label = (p == start ? "->" : "  ") + (accepting.contains(p) ? "*" : " ") + states[p]
            rows.append([label] + symbols.map {
                c in let set = direct(p, c)
                return dfa ? states[set.first!] : set.isEmpty ? "-" : setText(set)
            })
        }
        let widths = rows[0].indices.map {
            i in rows.map {
                $0[i].count
            }.max()!
        }
        return rows.map {
            row in
            var line = row.indices.map {
                row[$0].padding(toLength: widths[$0], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
            while line.last == " " {
                line.removeLast()
            }
            return line
        }
    }
    func show(_ name: String) -> String {
        var words = [dfa ? "DFA" : "NFA", name, states.joined(separator: ","), String(alphabet), states[start], accepting.isEmpty ? "-" : listText(accepting)]
        for p in states.indices {
            for c in alphabet + ["e"] {
                for q in direct(p, c).sorted() {
                    words.append("\(states[p]):\(c):\(states[q])")
                }
            }
        }
        return words.joined(separator: " ")
    }
}
func generated(_ dfa: Bool, _ prefix: String, _ size: Int, _ alphabet: [Character], _ start: Int, _ accepting: Set<Int>, _ transitions: Set<Transition>) -> Automaton {
    Automaton(dfa, (0..<size).map {
        "\(prefix)\($0)"
    },
    alphabet, start, accepting, transitions)
}
indirect enum Regular {
    case symbol(Character), sequence([Regular]), alternatives([Regular]), postfix(Character, Regular)
}
final class RegexParser {
    let text: [Character]
    var at = 0
    init(_ text: String) {
        self.text = Array(text)
    }
    var peek: Character {
        at < text.count ? text[at] : "\0"
    }
    func symbol(_ c: Character) -> Bool {
        c >= "a" && c <= "z" || c >= "0" && c <= "9"
    }
    func error() throws -> Never {
        try fail("syntax error at \(at + 1)")
    }
    func atom() throws -> Regular {
        let c = peek
        if symbol(c) {
            at += 1
            return .symbol(c)
        }
        if c == "(" {
            at += 1
            let r = try alternation()
            if peek != ")" {
                try error()
            }
            at += 1
            return r
        }
        try error()
    }
    func factor() throws -> Regular {
        var r = try atom()
        while "*+?".contains(peek) {
            let c = peek
            at += 1
            r = .postfix(c, r)
        }
        return r
    }
    func sequence() throws -> Regular {
        var list = [try factor()]
        while symbol(peek) || peek == "(" {
            list.append(try factor())
        }
        return list.count == 1 ? list[0] : .sequence(list)
    }
    func alternation() throws -> Regular {
        var list = [try sequence()]
        while peek == "|" {
            at += 1
            list.append(try sequence())
        }
        return list.count == 1 ? list[0] : .alternatives(list)
    }
}
func regexAutomaton(_ alphabet: [Character], _ text: String) throws -> Automaton {
    for c in text where (c >= "a" && c <= "z" || c >= "0" && c <= "9") && c != "e" && !alphabet.contains(c) {
        try fail("unknown symbol \(c)")
    }
    let parser = RegexParser(text)
    let tree = try parser.alternation()
    if parser.at != parser.text.count {
        try parser.error()
    }
    var size = 0
    var transitions = Set<Transition>()

    func state() -> Int {
        let s = size
        size += 1
        return s
    }
    func build(_ r: Regular) -> (Int, Int) {
        switch r {
        case let .symbol(c):
            let s = state()
            let f = state()
            transitions.insert(Transition(from: s, symbol: c, to: f))
            return (s, f)
        case let .sequence(list):
            let parts = list.map(build)
            for i in 0..<(parts.count - 1) {
                transitions.insert(Transition(from: parts[i].1, symbol: "e", to: parts[i + 1].0))
            }
            return (parts.first!.0, parts.last!.1)
        case let .alternatives(list):
            let s = state()
            let parts = list.map(build)
            let f = state()
            for (a, b) in parts {
                transitions.insert(Transition(from: s, symbol: "e", to: a))
                transitions.insert(Transition(from: b, symbol: "e", to: f))
            }
            return (s, f)
        case let .postfix(op, r):
            let s = state()
            let (a, b) = build(r)
            let f = state()
            transitions.insert(Transition(from: s, symbol: "e", to: a))
            transitions.insert(Transition(from: b, symbol: "e", to: f))
            if op != "?" {
                transitions.insert(Transition(from: b, symbol: "e", to: a))
            }
            if op != "+" {
                transitions.insert(Transition(from: s, symbol: "e", to: f))
            }
            return (s, f)
        }
    }
    let (s, f) = build(tree)
    return generated(false, "N", size, alphabet, s, [f], transitions)
}
final class Toolkit {
    var automata = [(String, Automaton)]()

    func get(_ name: String) throws -> Automaton {
        guard let a = automata.first(where: {
            $0.0 == name
        })?.1 else {
            try fail("unknown automaton \(name)")
        }
        return a
    }
    func fresh(_ name: String) throws {
        if automata.contains(where: {
            $0.0 == name
        }) {
            try fail("\(name) already exists")
        }
    }
    func register(_ name: String, _ a: Automaton, _ details: [String] = []) -> [String] {
        automata.append((name, a))
        return [a.summary(name)] + details
    }
    func define(_ dfa: Bool, _ args: [String]) throws -> [String] {
        if args.count < 5 {
            try fail("wrong number of arguments")
        }
        try fresh(args[0])
        var states = [String]()
        for name in args[1].components(separatedBy: ",") {
            if states.contains(name) {
                try fail("duplicate state \(name)")
            }
            states.append(name)
        }
        func state(_ name: String) throws -> Int {
            guard let s = states.firstIndex(of: name) else {
                try fail("unknown state \(name)")
            }
            return s
        }
        let start = try state(args[3])
        var accepting = Set<Int>()
        if args[4] != "-" {
            for name in args[4].components(separatedBy: ",") {
                let s = try state(name)
                if !accepting.insert(s).inserted {
                    try fail("duplicate state \(name)")
                }
            }
        }
        let alphabet = Array(args[2]).sorted()
        var transitions = Set<Transition>()
        for word in args.dropFirst(5) {
            let fields = word.components(separatedBy: ":")
            let p = try state(fields[0])
            let c = fields[1].first!
            if c == "e" && dfa {
                try fail("epsilon transition in DFA")
            }
            if c != "e" && !alphabet.contains(c) {
                try fail("unknown symbol \(c)")
            }
            let q = try state(fields[2])
            let t = Transition(from: p, symbol: c, to: q)
            if transitions.contains(t) {
                try fail("duplicate transition \(word)")
            }
            if dfa && transitions.contains(where: {
                $0.from == p && $0.symbol == c
            }) {
                try fail("conflicting transition \(word)")
            }
            transitions.insert(t)
        }
        if dfa {
            for p in states.indices {
                for c in alphabet {
                    if !transitions.contains(where: {
                        $0.from == p && $0.symbol == c
                    }) {
                        try fail("missing transition \(states[p]):\(c)")
                    }
                }
            }
        }
        return register(args[0], Automaton(dfa, states, alphabet, start, accepting, transitions))
    }
    func command(_ line: String) throws -> [String] {
        let fields = line.components(separatedBy: " ")
        let c = fields[0]
        let args = Array(fields.dropFirst())
        let count: Int
        switch c {
        case "DFA", "NFA":
            return try define(c == "DFA", args)
        case "REGEX":
            if args.count != 3 {
                try fail("wrong number of arguments")
            }
            try fresh(args[0])
            return register(args[0], try regexAutomaton(Array(args[1]).sorted(), args[2]))
        case "ACCEPT", "CLOSURE", "TODFA", "EPSFREE", "MINIMIZE", "EQUIV", "COMPLEMENT", "REVERSE", "STAR", "ENUM", "COUNT":
            count = 2
        case "UNION", "INTERSECT", "DIFF", "CONCAT":
            count = 3
        case "EMPTY", "FINITE", "INFO", "TABLE", "SHOW", "SYNC", "DELETE":
            count = 1
        case "LIST":
            count = 0
        default:
            try fail("unknown command \(c)")
        }
        if args.count != count {
            try fail("wrong number of arguments")
        }
        if c == "LIST" {
            return automata.isEmpty ? ["(none)"] : automata.map {
                $0.1.summary($0.0)
            }
        }
        let a = try get(args[0])
        let two = ["EQUIV", "UNION", "INTERSECT", "DIFF", "CONCAT"].contains(c)
        let b = two ? try get(args[1]) : nil
        let creates = ["TODFA", "EPSFREE", "MINIMIZE", "UNION", "INTERSECT", "DIFF", "COMPLEMENT", "REVERSE", "CONCAT", "STAR"].contains(c)
        if creates {
            try fresh(args.last!)
        }
        if ["MINIMIZE", "COMPLEMENT", "UNION", "INTERSECT", "DIFF", "SYNC"].contains(c) {
            if !a.dfa {
                try fail("\(args[0]) is not a DFA")
            }
            if two && !b!.dfa {
                try fail("\(args[1]) is not a DFA")
            }
        }
        if two && a.alphabet != b!.alphabet {
            try fail("alphabets differ")
        }
        switch c {
        case "DELETE":
            automata.removeAll {
                $0.0 == args[0]
            }
            return ["deleted \(args[0])"]
        case "ACCEPT":
            let word = args[1] == "e" ? "" : args[1]
            for ch in word where !a.alphabet.contains(ch) {
                try fail("unknown symbol \(ch)")
            }
            var set = a.initial()

            func text(_ s: Set<Int>) -> String {
                a.dfa ? a.states[s.first!] : a.setText(s)
            }
            var path = text(set)
            for ch in word {
                set = a.destination(set, ch)
                path += " -\(ch)-> \(text(set))"
            }
            return ["\(a.accepted(set) ? "ACCEPT" : "REJECT") \(path)"]
        case "CLOSURE":
            var set = Set<Int>()
            for name in args[1].components(separatedBy: ",") {
                guard let s = a.states.firstIndex(of: name) else {
                    try fail("unknown state \(name)")
                }
                set.insert(s)
            }
            return [a.setText(a.closure(set))]
        case "TABLE":
            return a.table()
        case "SHOW":
            return [a.show(args[0])]
        case "SYNC":
            return [a.synchronize()]
        case "EQUIV":
            let x = a.determinize().0
            let z = b!.determinize().0
            let first = Pair(p: x.start, q: z.start)
            var seen: Set<Pair> = [first]
            var queue = [(first, "")]
            var at = 0
            while at < queue.count {
                let (pair, word) = queue[at]
                at += 1
                let xp = x.accepting.contains(pair.p)
                let zq = z.accepting.contains(pair.q)
                if xp != zq {
                    return ["NOT EQUIVALENT: \(displayWord(word)) is accepted only by \(xp ? args[0] : args[1])"]
                }
                for ch in x.alphabet {
                    let next = Pair(p: x.delta(pair.p, ch), q: z.delta(pair.q, ch))
                    if seen.insert(next).inserted {
                        queue.append((next, word + String(ch)))
                    }
                }
            }
            return ["EQUIVALENT"]
        default:
            break
        }
        if ["ENUM", "COUNT", "EMPTY", "FINITE", "INFO"].contains(c) {
            let d = a.determinize().0
            switch c {
            case "ENUM":
                return [d.enumerate(Int(args[1])!)]
            case "COUNT":
                return [String(d.count(Int(args[1])!))]
            case "EMPTY":
                return [d.smallest().map {
                    "NOT EMPTY \(displayWord($0))"
                } ?? "EMPTY"]
            case "FINITE":
                return [d.language().map {
                    "FINITE \($0)"
                } ?? "INFINITE"]
            default:
                let deterministic = !a.transitions.contains {
                    $0.symbol == "e"
                } && a.states.indices.allSatisfy {
                    s in a.alphabet.allSatisfy {
                        a.direct(s, $0).count <= 1
                    }
                }
                let complete = a.states.indices.allSatisfy {
                    s in a.alphabet.allSatisfy {
                        !a.direct(s, $0).isEmpty
                    }
                }
                let size = d.language(false)
                let language = size == nil ? "infinite" : size == 0 ? "empty" : "finite"
                return [a.summary(args[0]), "  epsilon transitions: \(a.transitions.filter { $0.symbol == "e" }.count)", "  reachable: \(a.listText(a.reachable(false)))", "  live: \(a.listText(a.reachable(true)))", "  deterministic: \(deterministic ? "yes" : "no")", "  complete: \(complete ? "yes" : "no")", "  language: \(language)", "  minimal DFA states: \(d.minimize().0.states.count)"]
            }
        }
        let result: Automaton
        var details = [String]()
        switch c {
        case "TODFA":
            let pair = a.determinize()
            result = pair.0
            details = pair.1
        case "MINIMIZE":
            let pair = a.minimize()
            result = pair.0
            details = pair.1
        case "UNION", "INTERSECT", "DIFF":
            let pair = a.product(b!, c)
            result = pair.0
            details = pair.1
        case "COMPLEMENT":
            result = Automaton(true, a.states, a.alphabet, a.start, Set(a.states.indices.filter {
                !a.accepting.contains($0)
            }),
            a.transitions)
        case "EPSFREE":
            var accepting = Set<Int>()
            var transitions = Set<Transition>()
            for p in a.states.indices {
                let closure = a.closure([p])
                if a.accepted(closure) {
                    accepting.insert(p)
                }
                for ch in a.alphabet {
                    for q in a.destination(closure, ch) {
                        transitions.insert(Transition(from: p, symbol: ch, to: q))
                    }
                }
            }
            result = Automaton(false, a.states, a.alphabet, a.start, accepting, transitions)
        case "REVERSE", "STAR":
            var transitions = Set<Transition>()
            var accepting = Set<Int>()
            if c == "REVERSE" {
                for t in a.transitions {
                    transitions.insert(Transition(from: t.to + 1, symbol: t.symbol, to: t.from + 1))
                }
                for p in a.accepting {
                    transitions.insert(Transition(from: 0, symbol: "e", to: p + 1))
                }
                accepting.insert(a.start + 1)
            } else {
                for t in a.transitions {
                    transitions.insert(Transition(from: t.from + 1, symbol: t.symbol, to: t.to + 1))
                }
                transitions.insert(Transition(from: 0, symbol: "e", to: a.start + 1))
                accepting.insert(0)
                for p in a.accepting {
                    transitions.insert(Transition(from: p + 1, symbol: "e", to: a.start + 1))
                    accepting.insert(p + 1)
                }
            }
            result = generated(false, "N", a.states.count + 1, a.alphabet, 0, accepting, transitions)
        case "CONCAT":
            let z = b!
            let offset = a.states.count
            var transitions = a.transitions
            for t in z.transitions {
                transitions.insert(Transition(from: t.from + offset, symbol: t.symbol, to: t.to + offset))
            }
            for p in a.accepting {
                transitions.insert(Transition(from: p, symbol: "e", to: z.start + offset))
            }
            result = generated(false, "N", offset + z.states.count, a.alphabet, a.start, Set(z.accepting.map {
                $0 + offset
            }),
            transitions)
        default:
            fatalError("unreachable command")
        }
        return register(args.last!, result, details)
    }
}
let count = Int(readLine()!)!
let toolkit = Toolkit()
for _ in 0..<count {
    let line = readLine()!
    if line.hasPrefix("#") {
        continue
    }
    do {
        for result in try toolkit.command(line) {
            print(result)
        }
    } catch let e as Problem {
        print("error: \(e.reason)")
    } catch {
    }
}

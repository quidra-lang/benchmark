import Foundation

func freshName(_ symbol: String, _ rules: [String: [[String]]]) -> String {
    var proposed = String(symbol.dropLast()) + "'>"
    while rules[proposed] != nil { proposed = String(proposed.dropLast()) + "'>" }
    return proposed
}

func leadingReaches(_ rules: [String: [[String]]], _ source: String, _ target: String) -> Bool {
    var queue = [source], cursor = 0, discovered: Set<String> = [source]
    while cursor < queue.count {
        let current = queue[cursor]
        cursor += 1
        for symbols in rules[current] ?? [] {
            guard let neighbor = symbols.first, isNonterminal(neighbor) else { continue }
            if neighbor == target { return true }
            if discovered.insert(neighbor).inserted { queue.append(neighbor) }
        }
    }
    return false
}

func deduplicate(_ alternatives: [[String]]) -> [[String]] {
    var seen = Set<[String]>()
    return alternatives.filter { seen.insert($0).inserted }
}

func eliminateLeftRecursion(_ grammar: Grammar) -> (grammar: Grammar, log: [String]) {
    var g = grammar, log: [String] = []
    let initial = grammar.order
    for (index, lhs) in initial.enumerated() {
        for earlier in initial.prefix(index) {
            let current = g.rules[lhs]!
            if !current.contains(where: { $0.first == earlier }) || !leadingReaches(g.rules, earlier, lhs) { continue }
            var replacements: [[String]] = []
            for rhs in current {
                if rhs.first == earlier { for source in g.rules[earlier]! { replacements.append(source + Array(rhs.dropFirst())) } }
                else { replacements.append(rhs) }
            }
            g.rules[lhs] = deduplicate(replacements)
            log.append("substitute \(earlier) into \(lhs)")
        }
        var withoutCycle: [[String]] = []
        for rhs in g.rules[lhs]! {
            if rhs == [lhs] { log.append("remove cycle \(formatProduction(lhs, rhs))") } else { withoutCycle.append(rhs) }
        }
        let recursive = withoutCycle.filter { $0.first == lhs }.map { Array($0.dropFirst()) }
        if recursive.isEmpty { g.rules[lhs] = withoutCycle; continue }
        let nonrecursive = withoutCycle.filter { $0.first != lhs }, created = freshName(lhs, g.rules)
        g.rules[lhs] = nonrecursive.map { $0 + [created] }
        g.rules[created] = recursive.map { $0 + [created] } + [[]]
        g.order.insert(created, at: g.order.firstIndex(of: lhs)! + 1)
        log.append("eliminate left recursion in \(lhs) with \(created)")
    }
    return (g, log)
}

func longestCommonPrefix(_ rows: [[String]]) -> [String] {
    let limit = rows.map { $0.count }.min()!
    var position = 0
    while position < limit && rows.allSatisfy({ $0[position] == rows[0][position] }) { position += 1 }
    return Array(rows[0].prefix(position))
}

func leftFactor(_ grammar: Grammar) -> (grammar: Grammar, log: [String]) {
    var g = grammar, log: [String] = [], position = 0
    while position < g.order.count {
        let lhs = g.order[position]
        var current = g.rules[lhs]!, insertions: [String] = [], index = 0
        while index < current.count {
            let rhs = current[index]
            if rhs.isEmpty { index += 1; continue }
            let group = current.indices.filter { current[$0].first == rhs[0] }
            if group.count == 1 { index += 1; continue }
            let prefix = longestCommonPrefix(group.map { current[$0] }), created = freshName(lhs, g.rules)
            g.rules[created] = group.map { Array(current[$0].dropFirst(prefix.count)) }
            var alternatives: [[String]] = []
            for (i, row) in current.enumerated() {
                if i == group[0] { alternatives.append(prefix + [created]) } else if !group.contains(i) { alternatives.append(row) }
            }
            current = alternatives
            g.rules[lhs] = current
            insertions.append(created)
            log.append("left factor \(lhs) on \(formatAlternative(prefix)) with \(created)")
            index = group[0] + 1
        }
        g.order.insert(contentsOf: insertions, at: position + 1)
        position += 1
    }
    return (g, log)
}

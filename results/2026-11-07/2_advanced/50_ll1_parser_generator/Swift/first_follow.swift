import Foundation

func terminalOrder<S: Sequence>(_ terms: S) -> [String] where S.Element == String {
    let set = Set(terms)
    return set.filter { $0 != "$" }.sorted() + (set.contains("$") ? ["$"] : [])
}

func terminalsOf(_ grammar: Grammar) -> Set<String> {
    Set(grammar.order.flatMap { grammar.rules[$0]!.flatMap { $0.filter { !isNonterminal($0) } } })
}

func firstSequence(_ rhs: [String], _ nullable: [String: Bool], _ first: [String: Set<String>]) -> (terms: Set<String>, empty: Bool) {
    var found = Set<String>()
    for symbol in rhs {
        if !isNonterminal(symbol) { found.insert(symbol); return (found, false) }
        found.formUnion(first[symbol]!)
        if !nullable[symbol]! { return (found, false) }
    }
    return (found, true)
}

struct GrammarSets {
    let nullable: [String: Bool]
    let first: [String: Set<String>]
    let follow: [String: Set<String>]
    let nullablePasses: Int
    let firstPasses: Int
    let followPasses: Int
    let terminals: [String]

    init(_ grammar: Grammar) {
        var nullable = Dictionary(uniqueKeysWithValues: grammar.order.map { ($0, false) })
        var first: [String: Set<String>] = Dictionary(uniqueKeysWithValues: grammar.order.map { ($0, []) })
        var follow = first
        follow[grammar.start]!.insert("$")
        var nullablePasses = 0, firstPasses = 0, followPasses = 0
        while true {
            nullablePasses += 1
            var changed = false
            for lhs in grammar.order where !nullable[lhs]! {
                if grammar.rules[lhs]!.contains(where: { $0.allSatisfy { isNonterminal($0) && nullable[$0]! } }) { nullable[lhs] = true; changed = true }
            }
            if !changed { break }
        }
        while true {
            firstPasses += 1
            var changed = false
            for lhs in grammar.order {
                for rhs in grammar.rules[lhs]! {
                    let more = firstSequence(rhs, nullable, first).terms
                    if !more.isSubset(of: first[lhs]!) { first[lhs]!.formUnion(more); changed = true }
                }
            }
            if !changed { break }
        }
        while true {
            followPasses += 1
            var changed = false
            for lhs in grammar.order {
                for rhs in grammar.rules[lhs]! {
                    for (i, symbol) in rhs.enumerated() where isNonterminal(symbol) {
                        let sequence = firstSequence(Array(rhs.dropFirst(i + 1)), nullable, first)
                        var more = sequence.terms
                        if sequence.empty { more.formUnion(follow[lhs]!) }
                        if !more.isSubset(of: follow[symbol]!) { follow[symbol]!.formUnion(more); changed = true }
                    }
                }
            }
            if !changed { break }
        }
        self.nullable = nullable; self.first = first; self.follow = follow
        self.nullablePasses = nullablePasses; self.firstPasses = firstPasses; self.followPasses = followPasses
        terminals = terminalOrder(terminalsOf(grammar))
    }
}

import Foundation

enum PredictionReason: String { case first = "FIRST", follow = "FOLLOW" }
struct Production {
    let number: Int
    let lhs: String
    let rhs: [String]
    var predict: [String: PredictionReason] = [:]
    var notation: String { formatProduction(lhs, rhs) }
}

func numberProductions(_ grammar: Grammar) -> [Production] {
    var productions: [Production] = []
    for lhs in grammar.order { for rhs in grammar.rules[lhs]! { productions.append(Production(number: productions.count + 1, lhs: lhs, rhs: rhs)) } }
    return productions
}

struct TableKey: Hashable { let lhs: String; let token: String }
struct TableEntry { let number: Int; let reason: PredictionReason }
struct Conflict {
    let lhs: String
    let token: String
    let kind: String
    let entries: [TableEntry]
    let chosen: Int
}

struct ParseTable {
    let productions: [Production]
    let cells: [TableKey: [TableEntry]]
    let choices: [TableKey: Int]
    let conflicts: [Conflict]

    init(_ grammar: Grammar, _ sets: GrammarSets) {
        var productions = numberProductions(grammar), cells: [TableKey: [TableEntry]] = [:]
        for lhs in grammar.order { for token in sets.terminals + ["$"] { cells[TableKey(lhs: lhs, token: token)] = [] } }
        for index in productions.indices {
            let item = productions[index], sequence = firstSequence(item.rhs, sets.nullable, sets.first)
            var predicts = Dictionary(uniqueKeysWithValues: sequence.terms.map { ($0, PredictionReason.first) })
            if sequence.empty { for token in sets.follow[item.lhs]! where predicts[token] == nil { predicts[token] = .follow } }
            productions[index].predict = predicts
            for token in terminalOrder(predicts.keys) { cells[TableKey(lhs: item.lhs, token: token)]!.append(TableEntry(number: item.number, reason: predicts[token]!)) }
        }
        var choices: [TableKey: Int] = [:], conflicts: [Conflict] = []
        for lhs in grammar.order {
            for token in sets.terminals + ["$"] {
                let key = TableKey(lhs: lhs, token: token), entries = cells[key]!
                if entries.isEmpty { continue }
                let chosen = (entries.first { $0.reason == .first } ?? entries[0]).number
                choices[key] = chosen
                if entries.count >= 2 {
                    let allFirst = entries.allSatisfy { $0.reason == .first }, allFollow = entries.allSatisfy { $0.reason == .follow }
                    conflicts.append(Conflict(lhs: lhs, token: token, kind: allFirst ? "FIRST/FIRST" : allFollow ? "FOLLOW/FOLLOW" : "FIRST/FOLLOW", entries: entries, chosen: chosen))
                }
            }
        }
        self.productions = productions; self.cells = cells; self.choices = choices; self.conflicts = conflicts
    }
}

import Foundation

final class TreeNode {
    let symbol: String
    var mark: String?
    var children: [TreeNode]
    var label: String { symbol + (mark.map { " (" + $0 + ")" } ?? "") }
    init(_ symbol: String, mark: String? = nil, children: [TreeNode] = []) { self.symbol = symbol; self.mark = mark; self.children = children }
}

struct Trace {
    let step: Int
    let stack: [String]
    let input: [String]
    let action: String
}

enum RecoveryKind { case skip, pop, missing }
struct ParseEvent {
    let step: Int
    let kind: RecoveryKind
    let symbol: String
    let token: String
    let position: Int
}

struct ParseCounts {
    var predicts = 0
    var matches = 0
    var skips = 0
    var pops = 0
    var missings = 0
    var maxStack = 0
}

struct ParserResult {
    let root: TreeNode
    let trace: [Trace]
    let leftParse: [Int]
    let events: [ParseEvent]
    let counts: ParseCounts
}

typealias InputToken = (name: String, position: Int)

func parseTokens(_ tokens: [InputToken], _ grammar: Grammar, _ sets: GrammarSets, _ table: ParseTable) -> ParserResult {
    let input = tokens + [("$", tokens.count + 1)], root = TreeNode(grammar.start)
    var stack: [(symbol: String, node: TreeNode?)] = [("$", nil), (grammar.start, root)]
    var cursor = 0, leftParse: [Int] = [], trace: [Trace] = [], events: [ParseEvent] = []
    var counts = ParseCounts()
    while true {
        let step = trace.count + 1, top = stack.last!, current = input[cursor]
        counts.maxStack = max(counts.maxStack, stack.count)
        let beforeStack = stack.map { $0.symbol }, beforeInput = input.dropFirst(cursor).map { $0.name }
        let action: String
        var event: RecoveryKind?, terminate = false
        if top.symbol == "$" && current.name == "$" { action = "accept"; terminate = true }
        else if top.symbol == "$" { action = "error: skip " + current.name; event = .skip; cursor += 1; counts.skips += 1 }
        else if !isNonterminal(top.symbol) {
            if top.symbol == current.name { action = "match " + current.name; stack.removeLast(); cursor += 1; counts.matches += 1 }
            else { action = "error: missing " + top.symbol; top.node!.mark = "missing"; stack.removeLast(); counts.missings += 1; event = .missing }
        } else if let number = table.choices[TableKey(lhs: top.symbol, token: current.name)] {
            let production = table.productions[number - 1]
            action = "predict \(number): \(production.notation)"
            leftParse.append(number)
            stack.removeLast()
            if production.rhs.isEmpty { top.node!.children.append(TreeNode("%empty")) }
            else {
                let children = production.rhs.map { TreeNode($0) }
                top.node!.children += children
                for child in children.reversed() { stack.append((child.symbol, child)) }
            }
            counts.predicts += 1
        } else if current.name == "$" || sets.follow[top.symbol]!.contains(current.name) {
            action = "error: pop " + top.symbol; top.node!.mark = "error"; stack.removeLast(); counts.pops += 1; event = .pop
        } else { action = "error: skip " + current.name; cursor += 1; counts.skips += 1; event = .skip }
        trace.append(Trace(step: step, stack: beforeStack, input: beforeInput, action: action))
        if let event { events.append(ParseEvent(step: step, kind: event, symbol: top.symbol, token: current.name, position: current.position)) }
        if terminate { break }
    }
    return ParserResult(root: root, trace: trace, leftParse: leftParse, events: events, counts: counts)
}

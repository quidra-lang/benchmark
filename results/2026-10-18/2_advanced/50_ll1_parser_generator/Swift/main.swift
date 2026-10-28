import Foundation

func linesAt(_ path: String) throws -> [String] { Array(try String(contentsOfFile: path, encoding: .ascii).components(separatedBy: "\n").dropLast()) }
func list<S: Sequence>(_ heading: String, _ values: S) -> String where S.Element == String { heading + values.map { " " + $0 }.joined() }
func integerList<S: Sequence>(_ heading: String, _ values: S) -> String where S.Element == Int { list(heading, values.map(String.init)) }

func checkDeclarations(_ source: GrammarSource) -> [String] {
    if !source.hasDeclaration { return [] }
    return source.words.keys.sorted().filter { !source.declared.contains($0) }.map { "undeclared terminal \($0) at line \(source.words[$0]!)" }
}

func reachable(_ grammar: Grammar) -> Set<String> {
    var visited: Set<String> = [grammar.start], queue = [grammar.start], cursor = 0
    while cursor < queue.count {
        let lhs = queue[cursor]
        cursor += 1
        for rhs in grammar.rules[lhs] ?? [] {
            for symbol in rhs where isNonterminal(symbol) { if visited.insert(symbol).inserted { queue.append(symbol) } }
        }
    }
    return visited
}

func cleanGrammar(_ source: Grammar) -> (grammar: Grammar, diagnostics: [String]) {
    var g = source, diagnostics: [String] = []
    let defined = Set(g.order)
    let undefined = Set(g.order.flatMap { g.rules[$0]!.flatMap { $0.filter { isNonterminal($0) && !defined.contains($0) } } })
    for name in undefined.sorted(by: { String($0.dropFirst().dropLast()) < String($1.dropFirst().dropLast()) }) { diagnostics.append("undefined nonterminal \(name)") }
    for lhs in g.order {
        var kept: [[String]] = []
        for rhs in g.rules[lhs]! {
            if let bad = rhs.first(where: { undefined.contains($0) }) { diagnostics.append("removed \(formatProduction(lhs, rhs)) (undefined \(bad))") } else { kept.append(rhs) }
        }
        g.rules[lhs] = kept
    }
    var productive = Set<String>()
    while true {
        var changed = false
        for lhs in g.order where !productive.contains(lhs) {
            if g.rules[lhs]!.contains(where: { $0.allSatisfy { !isNonterminal($0) || productive.contains($0) } }) { productive.insert(lhs); changed = true }
        }
        if !changed { break }
    }
    let discarded = Set(g.order).subtracting(productive)
    for lhs in g.order where discarded.contains(lhs) { diagnostics.append("unproductive nonterminal \(lhs)") }
    g.order.removeAll { discarded.contains($0) }
    for lhs in g.order {
        var kept: [[String]] = []
        for rhs in g.rules[lhs]! {
            if let bad = rhs.first(where: { discarded.contains($0) }) { diagnostics.append("removed \(formatProduction(lhs, rhs)) (unproductive \(bad))") } else { kept.append(rhs) }
        }
        g.rules[lhs] = kept
    }
    for lhs in discarded { g.rules.removeValue(forKey: lhs) }
    let reached = reachable(g)
    for lhs in g.order where !reached.contains(lhs) { diagnostics.append("unreachable nonterminal \(lhs)") }
    g.order.removeAll { !reached.contains($0) }
    g.rules = Dictionary(uniqueKeysWithValues: g.order.map { ($0, g.rules[$0]!) })
    return (g, diagnostics)
}

func leftRecursionDiagnostics(_ grammar: Grammar) -> [String] {
    var diagnostics: [String] = []
    for start in grammar.order {
        var queue = [start], cursor = 0, visited: Set<String> = [start], parent: [String: String] = [:], path: [String]?
        while cursor < queue.count && path == nil {
            let lhs = queue[cursor]
            cursor += 1
            for rhs in grammar.rules[lhs]! {
                guard let successor = rhs.first, isNonterminal(successor) else { continue }
                if successor == start {
                    var backwards = [lhs]
                    while let previous = parent[backwards.last!] { backwards.append(previous) }
                    path = Array(backwards.reversed()) + [start]
                    break
                }
                if visited.insert(successor).inserted { parent[successor] = lhs; queue.append(successor) }
            }
        }
        if let path { diagnostics.append("left recursion: " + path.joined(separator: " -> ")) }
    }
    return diagnostics
}

func finalPruning(_ grammar: Grammar) -> (grammar: Grammar, log: [String], diagnostics: [String]) {
    var g = grammar
    let reached = reachable(g), removed = g.order.filter { !reached.contains($0) }
    g.order.removeAll { !reached.contains($0) }
    g.rules = Dictionary(uniqueKeysWithValues: g.order.map { ($0, g.rules[$0]!) })
    return (g, removed.map { "remove unreachable " + $0 }, removed.map { "unreachable after transformation " + $0 })
}

func grammarSummary(_ grammar: Grammar) -> String {
    let alternatives = grammar.order.flatMap { grammar.rules[$0]! }
    return "start=\(grammar.start) nonterminals=\(grammar.order.count) terminals=\(terminalsOf(grammar).count) productions=\(alternatives.count) empty=\(alternatives.filter { $0.isEmpty }.count) unit=\(alternatives.filter { $0.count == 1 && isNonterminal($0[0]) }.count)"
}

func grammarListing(_ grammar: Grammar, numbered: Bool = false) -> [String] {
    let total = grammar.order.reduce(0) { $0 + grammar.rules[$1]!.count }, width = String(total).count
    var lines: [String] = [], number = 0
    for lhs in grammar.order {
        for (index, rhs) in grammar.rules[lhs]!.enumerated() {
            number += 1
            let line = index == 0 ? formatProduction(lhs, rhs) : String(repeating: " ", count: lhs.count) + " | " + formatAlternative(rhs)
            lines.append(numbered ? String(repeating: " ", count: width - String(number).count) + "\(number)  " + line : line)
        }
    }
    return lines
}

func crossReference(_ grammar: Grammar) -> [String] {
    let productions = numberProductions(grammar)
    return (grammar.order + terminalOrder(terminalsOf(grammar))).map { symbol in
        let numbers = productions.filter { $0.rhs.contains(symbol) }.map { $0.number }
        let name = isNonterminal(symbol) ? symbol : "\"\(symbol)\""
        return numbers.isEmpty ? name + " not used" : integerList(name + " used in", numbers)
    }
}

func grammarFile(_ cleaned: Grammar, _ recursion: Grammar, _ factored: Grammar, _ finalGrammar: Grammar, _ recursionLog: [String], _ factoringLog: [String], _ finalLog: [String]) -> [String] {
    var lines = ["== cleaned grammar ==", grammarSummary(cleaned)] + grammarListing(cleaned)
    for (title, grammar, log, numbered) in [("left recursion elimination", recursion, recursionLog, false), ("left factoring", factored, factoringLog, false), ("final grammar", finalGrammar, finalLog, true)] {
        lines += ["", "== \(title) =="] + (log.isEmpty ? ["none"] : log) + [grammarSummary(grammar)] + grammarListing(grammar, numbered: numbered)
    }
    return lines + ["", "== cross reference =="] + crossReference(finalGrammar)
}

struct Measure: Equatable, Comparable {
    let length: Int
    let height: Int
    static func < (a: Measure, b: Measure) -> Bool { a.length == b.length ? a.height < b.height : a.length < b.length }
}

func alternativeMeasure(_ rhs: [String], _ scores: [String: Measure]) -> Measure? {
    if rhs.contains(where: { isNonterminal($0) && scores[$0] == nil }) { return nil }
    let length = rhs.reduce(0) { $0 + (isNonterminal($1) ? scores[$1]!.length : 1) }
    let height = (rhs.filter(isNonterminal).map { scores[$0]!.height }.max() ?? 0) + 1
    return Measure(length: length, height: height)
}

func shortestSentences(_ grammar: Grammar) -> (scores: [String: Measure], sentences: [String: [String]]) {
    var scores: [String: Measure] = [:]
    while true {
        var changed = false
        for lhs in grammar.order {
            for rhs in grammar.rules[lhs]! {
                if let candidate = alternativeMeasure(rhs, scores), scores[lhs] == nil || candidate < scores[lhs]! { scores[lhs] = candidate; changed = true }
            }
        }
        if !changed { break }
    }
    let selected = Dictionary(uniqueKeysWithValues: grammar.order.map { lhs in (lhs, grammar.rules[lhs]!.first { alternativeMeasure($0, scores) == scores[lhs]! }!) })
    var memo: [String: [String]] = [:]
    func expand(_ symbol: String) -> [String] {
        if !isNonterminal(symbol) { return [symbol] }
        if let result = memo[symbol] { return result }
        let result = selected[symbol]!.flatMap { expand($0) }
        memo[symbol] = result
        return result
    }
    for symbol in grammar.order { _ = expand(symbol) }
    return (scores, memo)
}

struct ContextParent {
    let production: Int
    let position: Int
    let lhs: String
    let before: [String]
    let after: [String]
}
struct Context { let before: [String]; let after: [String] }

func shortestContexts(_ grammar: Grammar, _ scores: [String: Measure], _ sentences: [String: [String]]) -> [String: Context] {
    let productions = numberProductions(grammar)
    var costs = [grammar.start: Measure(length: 0, height: 0)], parents: [String: ContextParent] = [:]
    while true {
        var changed = false
        for production in productions {
            guard let outer = costs[production.lhs] else { continue }
            for (index, symbol) in production.rhs.enumerated() where isNonterminal(symbol) && symbol != grammar.start {
                let before = Array(production.rhs.prefix(index)), after = Array(production.rhs.dropFirst(index + 1))
                let length = (before + after).reduce(0) { $0 + (isNonterminal($1) ? scores[$1]!.length : 1) }
                let cost = Measure(length: outer.length + length, height: outer.height + 1), key = [production.number, index]
                if costs[symbol] == nil || cost < costs[symbol]! || (cost == costs[symbol]! && key.lexicographicallyPrecedes([parents[symbol]!.production, parents[symbol]!.position])) {
                    costs[symbol] = cost
                    parents[symbol] = ContextParent(production: production.number, position: index, lhs: production.lhs, before: before, after: after)
                    changed = true
                }
            }
        }
        if !changed { break }
    }
    var memo = [grammar.start: Context(before: [], after: [])]
    func context(_ symbol: String) -> Context {
        if let value = memo[symbol] { return value }
        let parent = parents[symbol]!, outer = context(parent.lhs)
        let before = outer.before + parent.before.flatMap { isNonterminal($0) ? sentences[$0]! : [$0] }
        let after = parent.after.flatMap { isNonterminal($0) ? sentences[$0]! : [$0] } + outer.after
        let value = Context(before: before, after: after)
        memo[symbol] = value
        return value
    }
    for symbol in grammar.order { _ = context(symbol) }
    return memo
}

func exampleSentence(_ production: Production, _ sentences: [String: [String]], _ contexts: [String: Context]) -> [String] {
    let context = contexts[production.lhs]!, body = production.rhs.flatMap { isNonterminal($0) ? sentences[$0]! : [$0] }
    return context.before + body + context.after
}

func setsFile(_ grammar: Grammar, _ sets: GrammarSets, _ shortest: [String: [String]]) -> [String] {
    var lines = ["passes: nullable=\(sets.nullablePasses) first=\(sets.firstPasses) follow=\(sets.followPasses)", ""]
    for lhs in grammar.order {
        lines += [lhs, "  nullable: \(sets.nullable[lhs]! ? "yes" : "no")", list("  first:", terminalOrder(sets.first[lhs]!)), list("  follow:", terminalOrder(sets.follow[lhs]!)), list("  shortest:", shortest[lhs]!)]
    }
    return lines
}

func firstPath(_ production: Production, _ token: String, _ table: ParseTable, _ sets: GrammarSets) -> [Int] {
    let start = production.number
    var queue = [start], cursor = 0, visited: Set<Int> = [start], parent: [Int: Int] = [:]
    while cursor < queue.count {
        var current = queue[cursor]
        cursor += 1
        for symbol in table.productions[current - 1].rhs {
            if symbol == token {
                var path: [Int] = []
                while current != start { path.append(current); current = parent[current]! }
                return Array(path.reversed())
            }
            if isNonterminal(symbol) {
                for child in table.productions where child.lhs == symbol {
                    if visited.insert(child.number).inserted { parent[child.number] = current; queue.append(child.number) }
                }
                if !sets.nullable[symbol]! { break }
            } else { break }
        }
    }
    return []
}

func followPath(_ lhs: String, _ token: String, _ grammar: Grammar, _ table: ParseTable, _ sets: GrammarSets) -> [Int] {
    var queue = [(lhs, [Int]())], cursor = 0, visited: Set<String> = [lhs]
    while cursor < queue.count {
        let (symbol, path) = queue[cursor]
        cursor += 1
        if symbol == grammar.start && token == "$" { return path }
        for production in table.productions {
            for (index, child) in production.rhs.enumerated() where child == symbol {
                let sequence = firstSequence(Array(production.rhs.dropFirst(index + 1)), sets.nullable, sets.first)
                if sequence.terms.contains(token) { return path + [production.number] }
                if sequence.empty && visited.insert(production.lhs).inserted { queue.append((production.lhs, path + [production.number])) }
            }
        }
    }
    return []
}

func tableFile(_ grammar: Grammar, _ sets: GrammarSets, _ table: ParseTable, _ conflictsBefore: Int) -> [String] {
    var lines = ["== predict sets =="]
    for production in table.productions { lines += ["\(production.number): \(production.notation)", list("  predict:", terminalOrder(production.predict.keys))] }
    lines += ["", "== parse table =="]
    let tokens = sets.terminals + ["$"]
    var matrix = [[""] + tokens]
    for lhs in grammar.order {
        matrix.append([lhs] + tokens.map { token in
            let entries = table.cells[TableKey(lhs: lhs, token: token)]!
            return entries.isEmpty ? "." : entries.map { String($0.number) }.joined(separator: "/")
        })
    }
    let widths = matrix[0].indices.map { i in matrix.map { $0[i].count }.max()! }
    for row in matrix {
        var line = row[0] + String(repeating: " ", count: widths[0] - row[0].count)
        for i in 1..<row.count { line += "  " + String(repeating: " ", count: widths[i] - row[i].count) + row[i] }
        lines.append(line)
    }
    lines += ["", "== conflicts =="]
    if table.conflicts.isEmpty { lines.append("none") }
    for conflict in table.conflicts {
        lines.append("conflict \(conflict.lhs) on \(conflict.token): \(conflict.kind), chosen \(conflict.chosen)")
        for entry in conflict.entries {
            let production = table.productions[entry.number - 1]
            let path = entry.reason == .first ? firstPath(production, conflict.token, table, sets) : followPath(conflict.lhs, conflict.token, grammar, table, sets)
            let reason = path.isEmpty ? entry.reason.rawValue : integerList(entry.reason.rawValue + " via", path)
            lines.append("  \(entry.number): \(production.notation) (\(reason))")
        }
    }
    return lines + ["LL(1): \(table.conflicts.isEmpty ? "yes" : "no")", "conflicts before transformation: \(conflictsBefore)"]
}

func compactTree(_ node: TreeNode) -> TreeNode {
    var children: [TreeNode] = []
    for original in node.children where original.symbol != "%empty" {
        let child = compactTree(original)
        if isNonterminal(child.symbol) && child.mark == nil && child.children.isEmpty { continue }
        if isNonterminal(child.symbol) && child.symbol.contains("'") && child.mark == nil { children += child.children } else { children.append(child) }
    }
    if children.count == 1 && node.mark == nil { return children[0] }
    return TreeNode(node.symbol, mark: node.mark, children: children)
}

func treeLines(_ root: TreeNode) -> [String] {
    var lines = [root.label]
    func visit(_ node: TreeNode, _ prefix: String, _ last: Bool) {
        lines.append(prefix + (last ? "`-- " : "|-- ") + node.label)
        let nextPrefix = prefix + (last ? "    " : "|   ")
        for (index, child) in node.children.enumerated() { visit(child, nextPrefix, index == node.children.count - 1) }
    }
    for (index, child) in root.children.enumerated() { visit(child, "", index == root.children.count - 1) }
    return lines
}

func traceLines(_ trace: [Trace]) -> [String] {
    let rows = [["step", "stack", "input", "action"]] + trace.map { [String($0.step), $0.stack.joined(separator: " "), $0.input.joined(separator: " "), $0.action] }
    let widths = (0..<3).map { i in rows.map { $0[i].count }.max()! }
    return rows.map { row in (0..<3).map { row[$0] + String(repeating: " ", count: widths[$0] - row[$0].count) + "  " }.joined() + row[3] }
}

func leftmostDerivation(_ start: String, _ numbers: [Int], _ productions: [Production]) -> [String] {
    var symbols = [start], lines = ["  " + start]
    for number in numbers {
        let production = productions[number - 1], position = symbols.firstIndex(where: isNonterminal)!
        symbols.replaceSubrange(position...position, with: production.rhs)
        lines.append("  => " + formatAlternative(symbols))
    }
    return lines
}

struct EarleyState: Hashable {
    let lhs: String
    let rhs: [String]
    let dot: Int
    let origin: Int
    var advanced: EarleyState { EarleyState(lhs: lhs, rhs: rhs, dot: dot + 1, origin: origin) }
}

func recognizeOriginalLanguage(_ grammar: Grammar, _ tokens: [String]) -> Bool {
    var chart = Array(repeating: Set<EarleyState>(), count: tokens.count + 1)
    var pending = Array(repeating: [EarleyState](), count: tokens.count + 1)
    let seed = EarleyState(lhs: "<__root>", rhs: [grammar.start], dot: 0, origin: 0)
    chart[0].insert(seed); pending[0].append(seed)
    func add(_ index: Int, _ state: EarleyState) { if chart[index].insert(state).inserted { pending[index].append(state) } }
    for position in 0...tokens.count {
        var cursor = 0
        while cursor < pending[position].count {
            let state = pending[position][cursor]
            cursor += 1
            if state.dot == state.rhs.count {
                let waiting = pending[state.origin]
                for previous in waiting where previous.dot < previous.rhs.count && previous.rhs[previous.dot] == state.lhs { add(position, previous.advanced) }
            } else if isNonterminal(state.rhs[state.dot]) {
                let next = state.rhs[state.dot]
                for alternative in grammar.rules[next]! { add(position, EarleyState(lhs: next, rhs: alternative, dot: 0, origin: position)) }
                let completed = pending[position]
                for item in completed where item.lhs == next && item.dot == item.rhs.count && item.origin == position { add(position, state.advanced) }
            } else if position < tokens.count && state.rhs[state.dot] == tokens[position] { add(position + 1, state.advanced) }
        }
    }
    return chart[tokens.count].contains(seed.advanced)
}

struct ParsedInput {
    let original: [String]
    let unknownErrors: [String]
    let parsed: ParserResult
    let language: Bool
    var accepted: Bool { unknownErrors.isEmpty && parsed.events.isEmpty }
}

func parseInput(_ tokens: [String], _ grammar: Grammar, _ cleaned: Grammar, _ sets: GrammarSets, _ table: ParseTable) -> ParsedInput {
    let known = Set(sets.terminals)
    var kept: [InputToken] = [], errors: [String] = []
    for (index, token) in tokens.enumerated() {
        if known.contains(token) { kept.append((token, index + 1)) } else { errors.append("unknown \"\(token)\" at token \(index + 1); removed") }
    }
    return ParsedInput(original: tokens, unknownErrors: errors, parsed: parseTokens(kept, grammar, sets, table), language: recognizeOriginalLanguage(cleaned, tokens))
}

func errorString(_ event: ParseEvent, _ sets: GrammarSets, _ table: ParseTable) -> String {
    let unexpected = event.token == "$" ? "end of input" : "\"\(event.token)\" at token \(event.position)"
    let expected: String
    if isNonterminal(event.symbol) {
        let possible = (sets.terminals + ["$"]).filter { table.choices[TableKey(lhs: event.symbol, token: $0)] != nil }
        expected = terminalOrder(possible).map { $0 == "$" ? "$" : "\"\($0)\"" }.joined(separator: " ")
    } else { expected = event.symbol == "$" ? "$" : "\"\(event.symbol)\"" }
    let recovery: String
    switch event.kind {
    case .skip: recovery = "skipped \"\(event.token)\""
    case .pop: recovery = "popped \(event.symbol)"
    case .missing: recovery = "inserted \"\(event.symbol)\""
    }
    return "step \(event.step): unexpected \(unexpected); expected \(expected); \(recovery)"
}

func oneParseReport(_ number: Int, _ input: ParsedInput, _ grammar: Grammar, _ sets: GrammarSets, _ table: ParseTable) -> [String] {
    let parsed = input.parsed, errors = input.unknownErrors + input.parsed.events.map { errorString($0, sets, table) }, counts = input.parsed.counts
    var lines = ["== input \(number) ==", list("tokens:", input.original)] + traceLines(parsed.trace)
    lines += [integerList("left parse:", parsed.leftParse), "stats: steps=\(parsed.trace.count) predicts=\(counts.predicts) matches=\(counts.matches) max_stack=\(counts.maxStack)"]
    if !errors.isEmpty { lines += ["errors:"] + errors.map { "  " + $0 } }
    lines += [input.accepted ? "result: accepted" : "result: rejected (errors: \(errors.count))", "language: \(input.language ? "yes" : "no")"]
    if input.accepted { lines += ["derivation:"] + leftmostDerivation(grammar.start, parsed.leftParse, table.productions) }
    return lines + ["tree:"] + treeLines(parsed.root) + ["compact tree:"] + treeLines(compactTree(parsed.root))
}

func parseReport(_ inputs: [ParsedInput], _ grammar: Grammar, _ sets: GrammarSets, _ table: ParseTable, _ sentences: [String: [String]], _ contexts: [String: Context]) -> [String] {
    var lines: [String] = []
    for (index, input) in inputs.enumerated() { lines += oneParseReport(index + 1, input, grammar, sets, table) + [""] }
    let accepted = inputs.filter { $0.accepted }.count, inLanguage = inputs.filter { $0.language }.count
    let mismatches = inputs.indices.filter { inputs[$0].accepted != inputs[$0].language }.map { $0 + 1 }
    let used = Set(inputs.flatMap { $0.parsed.leftParse }), unused = table.productions.filter { !used.contains($0.number) }
    let unknown = inputs.reduce(0) { $0 + $1.unknownErrors.count }, skips = inputs.reduce(0) { $0 + $1.parsed.counts.skips }
    let pops = inputs.reduce(0) { $0 + $1.parsed.counts.pops }, missings = inputs.reduce(0) { $0 + $1.parsed.counts.missings }
    lines += ["== summary ==", "inputs=\(inputs.count) accepted=\(accepted) rejected=\(inputs.count - accepted) in_language=\(inLanguage)", integerList("mismatches:", mismatches),
              "recovery: unknown=\(unknown) skip=\(skips) pop=\(pops) missing=\(missings)", "coverage: \(used.count) of \(table.productions.count) productions used", integerList("unused:", unused.map { $0.number })]
    for production in unused {
        let sentence = exampleSentence(production, sentences, contexts)
        let parsed = parseTokens(sentence.enumerated().map { ($0.element, $0.offset + 1) }, grammar, sets, table)
        lines += ["  \(production.number): \(production.notation)", list("    example:", sentence),
                  parsed.events.isEmpty ? "    result: accepted" : "    result: rejected (errors: \(parsed.events.count))", "    used: \(parsed.leftParse.contains(production.number) ? "yes" : "no")"]
    }
    return lines
}

func save(_ filename: String, _ lines: [String]) throws { try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + filename, atomically: false, encoding: .ascii) }

let source = parseGrammar(try linesAt("input/grammar.bnf"))
let cleaned = cleanGrammar(source.grammar)
let recursionDiagnostics = leftRecursionDiagnostics(cleaned.grammar)
let recursion = eliminateLeftRecursion(cleaned.grammar)
let factored = leftFactor(recursion.grammar)
let pruned = finalPruning(factored.grammar)
let finalGrammar = pruned.grammar
let sets = GrammarSets(finalGrammar), table = ParseTable(finalGrammar, sets)
let beforeSets = GrammarSets(cleaned.grammar), beforeTable = ParseTable(cleaned.grammar, beforeSets)
let shortest = shortestSentences(finalGrammar)
let contexts = shortestContexts(finalGrammar, shortest.scores, shortest.sentences)
let tokensByLine = try linesAt("input/inputs.txt").map { $0.isEmpty ? [] : $0.components(separatedBy: " ") }
let inputs = tokensByLine.map { parseInput($0, finalGrammar, cleaned.grammar, sets, table) }
let unusedDeclarations = source.hasDeclaration ? source.declared.subtracting(terminalsOf(finalGrammar)).sorted().map { "unused token " + $0 } : []
var diagnostics = source.diagnostics + checkDeclarations(source) + cleaned.diagnostics + recursionDiagnostics + pruned.diagnostics + unusedDeclarations
diagnostics.append(table.conflicts.isEmpty ? "result: LL(1)" : "result: not LL(1) (conflicts: \(table.conflicts.count))")
try save("grammar.txt", grammarFile(cleaned.grammar, recursion.grammar, factored.grammar, finalGrammar, recursion.log, factored.log, pruned.log))
try save("sets.txt", setsFile(finalGrammar, sets, shortest.sentences))
try save("table.txt", tableFile(finalGrammar, sets, table, beforeTable.conflicts.count))
try save("parses.txt", parseReport(inputs, finalGrammar, sets, table, shortest.sentences, contexts))
try save("diagnostics.txt", diagnostics)

import Foundation

struct Grammar {
    var order: [String]
    var rules: [String: [[String]]]
    var start: String
}

struct GrammarSource {
    let grammar: Grammar
    let declared: Set<String>
    let hasDeclaration: Bool
    let words: [String: Int]
    let diagnostics: [String]
}

enum TokenKind: Equatable { case nonterminal, terminal, word, definition, separator, directive, invalid }
struct Token {
    let kind: TokenKind
    let value: String
    let start: Int
    let end: Int
}

func isNonterminal(_ symbol: String) -> Bool { symbol.hasPrefix("<") && symbol.hasSuffix(">") }
func formatAlternative(_ symbols: [String]) -> String { symbols.isEmpty ? "%empty" : symbols.joined(separator: " ") }
func formatProduction(_ lhs: String, _ rhs: [String]) -> String { lhs + " -> " + formatAlternative(rhs) }
func letter(_ byte: UInt8) -> Bool { (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) }
func wordCharacter(_ byte: UInt8) -> Bool { letter(byte) || (byte >= 48 && byte <= 57) || byte == 95 }

func lexLine(_ line: String) -> [Token] {
    let bytes = Array(line.utf8)
    func substring(_ start: Int, _ end: Int) -> String { String(decoding: bytes[start..<end], as: UTF8.self) }
    var tokens: [Token] = [], i = 0
    while i < bytes.count {
        if bytes[i] == 32 { i += 1; continue }
        if bytes[i] == 35 { break }
        let start = i
        var kind: TokenKind = .invalid, value = substring(i, i + 1), next = i + 1
        if bytes[i] == 60 {
            var j = i + 1
            if j < bytes.count && letter(bytes[j]) {
                j += 1
                while j < bytes.count && wordCharacter(bytes[j]) { j += 1 }
                if j < bytes.count && bytes[j] == 62 { kind = .nonterminal; next = j + 1; value = substring(i, next) }
            }
        } else if bytes[i] == 34 {
            var j = i + 1
            while j < bytes.count && bytes[j] != 34 && bytes[j] != 32 { j += 1 }
            if j > i + 1 && j < bytes.count && bytes[j] == 34 { kind = .terminal; value = substring(i + 1, j); next = j + 1 }
        } else if letter(bytes[i]) {
            var j = i + 1
            while j < bytes.count && wordCharacter(bytes[j]) { j += 1 }
            kind = .word; value = substring(i, j); next = j
        } else if i + 2 < bytes.count && substring(i, i + 3) == "::=" {
            kind = .definition; value = "::="; next = i + 3
        } else if bytes[i] == 124 { kind = .separator; value = "|" }
        else if bytes[i] == 37 {
            var j = i + 1
            while j < bytes.count && letter(bytes[j]) { j += 1 }
            let name = substring(i + 1, j)
            if ["empty", "start", "token"].contains(name) { kind = .directive; value = "%" + name; next = j }
        }
        i = next
        tokens.append(Token(kind: kind, value: value, start: start + 1, end: i))
        if kind == .invalid { break }
    }
    return tokens
}

enum LineKind: Equatable { case blank, rule, continuation, start, declaration, malformed }
struct ParsedLine {
    let kind: LineKind
    var lhs: String = ""
    var alternatives: [[String]] = []
    var words: [String] = []
    var error: Int? = nil
}

func errorColumn(_ tokens: [Token], _ cursor: Int) -> Int { cursor < tokens.count ? tokens[cursor].start : tokens.last!.end + 1 }

func parseAlternatives(_ tokens: [Token], _ start: Int) -> (alternatives: [[String]], error: Int?) {
    var alternatives: [[String]] = [], cursor = start
    while true {
        if cursor >= tokens.count { return ([], errorColumn(tokens, cursor)) }
        let first = tokens[cursor]
        var alternative: [String] = []
        if first.kind == .directive && first.value == "%empty" {
            cursor += 1
            if cursor < tokens.count && tokens[cursor].kind != .separator { return ([], errorColumn(tokens, cursor)) }
        } else if [TokenKind.nonterminal, .terminal, .word].contains(first.kind) {
            while cursor < tokens.count && [TokenKind.nonterminal, .terminal, .word].contains(tokens[cursor].kind) { alternative.append(tokens[cursor].value); cursor += 1 }
        } else { return ([], errorColumn(tokens, cursor)) }
        alternatives.append(alternative)
        if cursor >= tokens.count { return (alternatives, nil) }
        if tokens[cursor].kind != .separator { return ([], errorColumn(tokens, cursor)) }
        cursor += 1
    }
}

func parseLine(_ tokens: [Token]) -> ParsedLine {
    guard let first = tokens.first else { return ParsedLine(kind: .blank) }
    func malformed(_ cursor: Int) -> ParsedLine { ParsedLine(kind: .malformed, error: errorColumn(tokens, cursor)) }
    if first.kind == .nonterminal {
        if tokens.count < 2 { return malformed(tokens.count) }
        if tokens[1].kind != .definition { return malformed(1) }
        let alternatives = parseAlternatives(tokens, 2)
        return ParsedLine(kind: .rule, lhs: first.value, alternatives: alternatives.alternatives, error: alternatives.error)
    }
    if first.kind == .separator {
        let alternatives = parseAlternatives(tokens, 1)
        return ParsedLine(kind: .continuation, alternatives: alternatives.alternatives, error: alternatives.error)
    }
    if first.kind == .directive && first.value == "%start" {
        if tokens.count < 2 { return malformed(tokens.count) }
        if tokens[1].kind != .nonterminal { return malformed(1) }
        if tokens.count > 2 { return malformed(2) }
        return ParsedLine(kind: .start, lhs: tokens[1].value)
    }
    if first.kind == .directive && first.value == "%token" {
        if tokens.count < 2 { return malformed(tokens.count) }
        for i in 1..<tokens.count where tokens[i].kind != .word { return malformed(i) }
        return ParsedLine(kind: .declaration, words: tokens.dropFirst().map { $0.value })
    }
    return malformed(0)
}

func parseGrammar(_ lines: [String]) -> GrammarSource {
    var grammar = Grammar(order: [], rules: [:], start: "")
    var declared = Set<String>(), hasDeclaration = false, words: [String: Int] = [:], diagnostics: [String] = []
    var attachment: String?
    for (index, line) in lines.enumerated() {
        let number = index + 1, tokens = lexLine(line), parsed = parseLine(tokens)
        if let error = parsed.error { diagnostics.append("line \(number): syntax error at column \(error)"); attachment = nil; continue }
        if parsed.kind == .blank { continue }
        var lhs = parsed.lhs
        switch parsed.kind {
        case .rule:
            attachment = lhs
            if grammar.rules[lhs] == nil { grammar.order.append(lhs); grammar.rules[lhs] = [] }
        case .continuation:
            guard let attached = attachment else { diagnostics.append("line \(number): continuation without a rule"); continue }
            lhs = attached
        case .start:
            attachment = nil
            if grammar.start.isEmpty { grammar.start = lhs } else { diagnostics.append("line \(number): duplicate %start") }
        case .declaration: attachment = nil; hasDeclaration = true; declared.formUnion(parsed.words)
        default: break
        }
        if parsed.kind == .rule || parsed.kind == .continuation {
            for token in tokens where token.kind == .word && words[token.value] == nil { words[token.value] = number }
            for alternative in parsed.alternatives {
                if grammar.rules[lhs]!.contains(alternative) { diagnostics.append("line \(number): duplicate alternative \(formatProduction(lhs, alternative))") }
                else { grammar.rules[lhs]!.append(alternative) }
            }
        }
    }
    if grammar.start.isEmpty { grammar.start = grammar.order[0] }
    return GrammarSource(grammar: grammar, declared: declared, hasDeclaration: hasDeclaration, words: words, diagnostics: diagnostics)
}

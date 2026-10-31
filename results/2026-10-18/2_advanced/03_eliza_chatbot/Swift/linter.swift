let diagnosticCodes = ["SYNTAX", "ORPHAN", "DUPLICATE", "KEY_NO_DECOMP", "KEY_UNREACHABLE", "SYNON_UNUSED", "PRE_CHAIN", "SYNON_UNKNOWN", "RULE_NO_REASM", "RULE_SHADOWED", "REF_UNBOUND", "TARGET_UNDEFINED", "TARGET_CYCLE"]
let errorCodes: Set<String> = ["SYNTAX", "ORPHAN", "DUPLICATE", "SYNON_UNKNOWN", "REF_UNBOUND", "TARGET_UNDEFINED", "TARGET_CYCLE"]

func references(_ text: String) -> [Int] {
    let bytes = Array(text.utf8)
    guard bytes.count >= 3 else { return [] }
    return (0..<(bytes.count - 2)).compactMap { index in
        bytes[index] == 40 && (48...57).contains(bytes[index + 1]) && bytes[index + 2] == 41 ? Int(bytes[index + 1] - 48) : nil
    }
}

func lint(_ script: Script) -> [Diagnostic] {
    var found = script.diagnostics
    func add(_ line: Int, _ code: String, _ message: String) { found.append(Diagnostic(line: line, code: code, message: message)) }
    let replacementWords = Set(script.pres.flatMap { $0.replacement })
    let targets = Set(script.items.filter { ["GOTO", "RESTATE"].contains($0.kind) }.map { $0.arguments[0] })
    let usedGroups = Set(script.rules.flatMap { $0.pattern }.filter { $0.hasPrefix("@") }.map { String($0.dropFirst()) })
    var graph: [String: [String]] = [:]
    for keyword in script.keywords {
        graph[keyword.word] = keyword.decomps.flatMap { script.rules[$0].items }.map { script.items[$0] }.filter {
            ["GOTO", "RESTATE"].contains($0.kind) && script.keywordMap[$0.arguments[0]] != nil
        }.map { $0.arguments[0] }
    }
    func reaches(_ start: String, _ goal: String) -> Bool {
        var seen: Set<String> = []
        var pending = [start]
        while let word = pending.popLast() {
            if word == goal { return true }
            if seen.insert(word).inserted { pending += graph[word]! }
        }
        return false
    }
    func unknown(_ pattern: [String]) -> [String] {
        pattern.filter { $0.hasPrefix("@") && script.groupWords[String($0.dropFirst())] == nil }
    }
    for keyword in script.keywords {
        if keyword.decomps.isEmpty { add(keyword.line, "KEY_NO_DECOMP", "keyword \(keyword.word) has no DECOMP") }
        if script.pre[keyword.word] != nil && !replacementWords.contains(keyword.word) && !targets.contains(keyword.word) { add(keyword.line, "KEY_UNREACHABLE", "keyword \(keyword.word) is replaced by PRE") }
        for rules in [keyword.memories, keyword.decomps] {
            for (position, ruleID) in rules.enumerated() {
                let rule = script.rules[ruleID]
                for element in unknown(rule.pattern) { add(rule.line, "SYNON_UNKNOWN", "unknown group \(element.dropFirst())") }
                if rule.items.isEmpty { add(rule.line, "RULE_NO_REASM", "rule has no reassembly") }
                if unknown(rule.pattern).isEmpty, let shadow = rules.prefix(position).map({ script.rules[$0] }).first(where: {
                    unknown($0.pattern).isEmpty && patternCovers($0.pattern, later: rule.pattern, groups: script.groupWords)
                }) { add(rule.line, "RULE_SHADOWED", "pattern is shadowed by line \(shadow.line)") }
                let wildcards = rule.pattern.filter(isWildcard).count
                for itemID in rule.items {
                    let item = script.items[itemID]
                    let refs: [Int]
                    if item.kind == "REASM" { refs = references(item.text) }
                    else if item.kind == "RESTATE" { refs = item.arguments.dropFirst().filter(isReference).map { Int(Array($0.utf8)[1] - 48) } }
                    else { refs = [] }
                    for reference in refs where reference == 0 || reference > wildcards { add(item.line, "REF_UNBOUND", "reference (\(reference)) is not bound") }
                    if ["GOTO", "RESTATE"].contains(item.kind) {
                        let target = item.arguments[0]
                        if script.keywordMap[target] == nil { add(item.line, "TARGET_UNDEFINED", "target \(target) is not a keyword") }
                        else if reaches(target, keyword.word) { add(item.line, "TARGET_CYCLE", "edge \(keyword.word) -> \(target) is on a cycle") }
                    }
                }
            }
        }
    }
    for group in script.groups where !usedGroups.contains(group.name) { add(group.line, "SYNON_UNUSED", "group \(group.name) is never used") }
    for pre in script.pres {
        for word in pre.replacement where script.pre[word] != nil { add(pre.line, "PRE_CHAIN", "replacement \(word) is itself replaced by PRE") }
    }
    return found.enumerated().sorted {
        if $0.element.line != $1.element.line { return $0.element.line < $1.element.line }
        let left = diagnosticCodes.firstIndex(of: $0.element.code)!
        let right = diagnosticCodes.firstIndex(of: $1.element.code)!
        return left == right ? $0.offset < $1.offset : left < right
    }.map { $0.element }
}

func lintLines(_ diagnostics: [Diagnostic]) -> [String] {
    if diagnostics.isEmpty { return ["OK"] }
    let errors = diagnostics.filter { errorCodes.contains($0.code) }.count
    return diagnostics.map { "\($0.line) \($0.code) \($0.message)" } + ["TOTAL \(diagnostics.count) errors=\(errors) warnings=\(diagnostics.count - errors)"]
}

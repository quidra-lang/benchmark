import Foundation

func stringNotation(_ text: String) -> String {
    var result = "\""
    for byte in text.utf8 {
        switch byte {
        case 92: result += "\\\\"
        case 34: result += "\\\""
        case 10: result += "\\n"
        case 9: result += "\\t"
        default: result += asciiText([byte])
        }
    }
    return result + "\""
}

func valueNotation(_ value: Value) -> String {
    switch value {
    case .string(let text): return stringNotation(text)
    case .integer(let number): return String(number)
    case .boolean(let flag): return flag ? "true" : "false"
    case .atom(let text): return text
    case .list(let items): return "[" + items.map(valueNotation).joined(separator: ", ") + "]"
    }
}

func shown(_ output: OutputKey) -> String {
    output.spec?.secret == true ? "********" : output.notation
}

private func normalizedBlock(_ profile: Profile) -> [String] {
    var lines = ["profile \(profile.name)"]
    var previous: String?
    for key in profile.outputs.keys.sorted(by: keyLess) {
        let (section, name) = splitKey(key)
        if section != previous {
            lines.append("[\(section)]")
            previous = section
        }
        lines.append("\(name) = \(shown(profile.outputs[key]!))")
    }
    return lines
}

private func diagnosticsBlock(_ profile: Profile) -> [String] {
    ["profile \(profile.name) errors \(profile.errors) warnings \(profile.warnings)"] +
    profile.sortedDiagnostics.map { "\($0.origin.text) \($0.code) \($0.message)" }
}

private func reportBlock(_ profile: Profile) -> [String] {
    var lines = ["profile \(profile.name)", "includes"]
    lines += profile.tree.map { String(repeating: " ", count: 2 + 2 * $0.depth) + $0.text }
    lines.append("overridden")
    var histories: [String] = []
    for key in profile.outputs.keys.sorted(by: keyLess) {
        let history = profile.outputs[key]!.definition.history
        if history.count >= 2 {
            histories.append("  \(key): " + history.map(\.text).joined(separator: " -> "))
        }
    }
    lines += histories.isEmpty ? ["  (none)"] : histories
    lines.append("keys \(profile.outputs.count) documents \(profile.documentKeys) manifest \(profile.manifestKeys) defaults \(profile.defaultKeys)")
    lines.append("dropped \(profile.dropped)")
    lines.append("errors \(profile.errors) warnings \(profile.warnings)")
    return lines
}

private func diffBlock(_ diff: ProfileDiff) -> [String] {
    var lines = ["diff \(diff.first) -> \(diff.second): \(diff.added) added, \(diff.removed) removed, \(diff.changed) changed"]
    for entry in diff.entries {
        switch entry.mark {
        case "+": lines.append("+ \(entry.key) = \(shown(entry.after!))")
        case "-": lines.append("- \(entry.key) = \(shown(entry.before!))")
        default: lines.append("~ \(entry.key): \(shown(entry.before!)) -> \(shown(entry.after!))")
        }
    }
    return lines
}

func writeOutputs(profiles: [Profile], diffs: [ProfileDiff]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true, attributes: nil)
    func write(_ filename: String, blocks: [[String]]) throws {
        let text = blocks.map { $0.joined(separator: "\n") }.joined(separator: "\n\n") + "\n"
        try text.write(toFile: "output/" + filename, atomically: true, encoding: .ascii)
    }
    try write("normalized.txt", blocks: profiles.map(normalizedBlock))
    try write("diagnostics.txt", blocks: profiles.map(diagnosticsBlock))
    try write("diff.txt", blocks: diffs.map(diffBlock))
    try write("report.txt", blocks: profiles.map(reportBlock))
}

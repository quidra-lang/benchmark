func reflect(_ words: [String], post: [String: [String]]) -> [String] {
    words.flatMap { post[$0] ?? [$0] }
}

func binding(_ bindings: [[String]], number: Int) -> [String] {
    number >= 1 && number <= bindings.count ? bindings[number - 1] : []
}

func buildReply(_ template: String, bindings: [[String]], post: [String: [String]]) -> String {
    let bytes = Array(template.utf8)
    var text = ""
    var index = 0
    while index < bytes.count {
        if index + 3 <= bytes.count && bytes[index] == 40 && (48...57).contains(bytes[index + 1]) && bytes[index + 2] == 41 {
            text += reflect(binding(bindings, number: Int(bytes[index + 1] - 48)), post: post).joined(separator: " ")
            index += 3
        } else { text += String(UnicodeScalar(bytes[index])); index += 1 }
    }
    let reply = text.split(separator: " ").joined(separator: " ")
    guard let first = reply.utf8.first, (97...122).contains(first) else { return reply }
    return String(UnicodeScalar(first - 32)) + reply.dropFirst()
}

func restatedWords(_ arguments: [String], bindings: [[String]]) -> [String] {
    arguments.flatMap { isReference($0) ? binding(bindings, number: Int(Array($0.utf8)[1] - 48)) : [$0] }
}

func elizaLines(_ text: String) -> [String] {
    let words = text.split(separator: " ").map(String.init)
    var lines = ["ELIZA: \(words[0])"]
    for word in words.dropFirst() {
        if lines[lines.count - 1].count + 1 + word.count <= 72 { lines[lines.count - 1] += " \(word)" }
        else { lines.append("       \(word)") }
    }
    return lines
}

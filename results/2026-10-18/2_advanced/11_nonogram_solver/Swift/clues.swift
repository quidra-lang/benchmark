func runClue(_ cells: [Int]) -> [Int] {
    var result: [Int] = [], run = 0
    for state in cells { if state == filled { run += 1 } else if run > 0 { result.append(run); run = 0 } }
    if run > 0 { result.append(run) }
    return result
}
func clueText(_ clue: [Int], _ separator: String = " ") -> String { clue.isEmpty ? "0" : clue.map(String.init).joined(separator: separator) }
func isClueLine(_ text: String) -> Bool { !text.isEmpty && text.utf8.allSatisfy { $0 == 32 || (48...57).contains($0) } }
func parseClue(_ text: String) -> [Int]? {
    if text == "0" { return [] }
    let tokens = text.split(separator: " ", omittingEmptySubsequences: false)
    var result: [Int] = []
    for token in tokens {
        let bytes = Array(token.utf8)
        if !(1...2).contains(bytes.count) || bytes[0] == 48 || !bytes.allSatisfy({ (48...57).contains($0) }) { return nil }
        result.append(Int(token)!)
    }
    return result
}
func clueFits(_ clue: [Int], _ length: Int) -> Bool { clue.reduce(0, +) + clue.count - 1 <= length }

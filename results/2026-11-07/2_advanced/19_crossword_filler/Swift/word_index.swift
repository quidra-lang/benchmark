func asciiLess(_ first: String, _ second: String) -> Bool { first.utf8.lexicographicallyPrecedes(second.utf8) }
func isValidWord(_ text: String) -> Bool { (3...15).contains(text.utf8.count) && text.utf8.allSatisfy { 65...90 ~= $0 } }
func isValidInteger(_ text: String, _ low: Int, _ high: Int) -> Bool {
    guard !text.isEmpty, !text.hasPrefix("0"), text.utf8.count <= String(high).count,
        text.utf8.allSatisfy({ 48...57 ~= $0 }), let value = Int(text) else { return false }
    return low <= value && value <= high
}
func wordLineError(_ line: String) -> String? {
    if line.utf8.filter({ $0 == 32 }).count != 1 { return "bad format" }
    let parts = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    if !isValidWord(parts[0]) { return "bad word" }
    return isValidInteger(parts[1], 1, 100) ? nil : "bad score"
}
func clueLineError(_ line: String) -> String? {
    if line.utf8.filter({ $0 == 124 }).count != 1 { return "bad format" }
    let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    if !isValidWord(parts[0]) { return "bad word" }
    return (1...60).contains(parts[1].utf8.count) && !parts[1].hasPrefix(" ") && !parts[1].hasSuffix(" ") ? nil : "bad clue"
}
func matches(_ word: [UInt8], _ pattern: [UInt8]) -> Bool { zip(word, pattern).allSatisfy { letter, mark in mark == 46 || mark == letter } }
struct Word { let text: String; let letters: [UInt8]; let score: Int }
private struct LetterKey: Hashable { let length: Int; let position: Int; let letter: UInt8 }
struct WordIndex {
    let words: [Word]
    let lookup: [String: Int]
    let byLength: [Int: [Int]]
    private let byLetter: [LetterKey: [Int]]
    init(_ scores: [String: Int]) {
        let ranked = scores.keys.sorted { scores[$0] == scores[$1] ? asciiLess($0, $1) : scores[$0]! > scores[$1]! }
        var words: [Word] = []
        var lookup: [String: Int] = [:]
        var byLength: [Int: [Int]] = [:]
        var byLetter: [LetterKey: [Int]] = [:]
        for (id, text) in ranked.enumerated() {
            let letters = Array(text.utf8)
            lookup[text] = id
            byLength[letters.count, default: []].append(id)
            for (position, letter) in letters.enumerated() { byLetter[LetterKey(length: letters.count, position: position, letter: letter), default: []].append(id) }
            words.append(Word(text: text, letters: letters, score: scores[text]!))
        }
        self.words = words
        self.lookup = lookup
        self.byLength = byLength
        self.byLetter = byLetter
    }
    func candidates(_ pattern: [UInt8], _ minimum: Int, _ used: Set<Int>) -> [Int] {
        var pool = byLength[pattern.count, default: []]
        for (position, mark) in pattern.enumerated() where mark != 46 {
            let bucket = byLetter[LetterKey(length: pattern.count, position: position, letter: mark), default: []]
            if bucket.count < pool.count { pool = bucket }
        }
        return pool.prefix { words[$0].score >= minimum }.filter { !used.contains($0) && matches(words[$0].letters, pattern) }
    }
}

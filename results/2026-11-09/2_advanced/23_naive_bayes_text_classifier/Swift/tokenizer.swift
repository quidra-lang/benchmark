import Foundation

struct Tokens {
    let rawCount: Int
    let stopwordCount: Int
    let shortCount: Int
    let words: [String]
    let bigrams: [String]
    private let combined: [String]
    init(_ text: String, _ stopwords: Set<String>) {
        var raw: [String] = [], word: [UInt8] = []
        for byte in Array(text.utf8) + [32] {
            if (65...90).contains(byte) { word.append(byte + 32) }
            else if (97...122).contains(byte) || (48...57).contains(byte) { word.append(byte) }
            else if !word.isEmpty { raw.append(String(bytes: word, encoding: .utf8)!); word.removeAll(keepingCapacity: true) }
        }
        var stopwordCount = 0, shortCount = 0
        var words: [String] = []
        for word in raw {
            if stopwords.contains(word) { stopwordCount += 1 }
            else if word.utf8.count == 1 { shortCount += 1 }
            else { words.append(word) }
        }
        let bigrams = zip(words, words.dropFirst()).map { $0.0 + "_" + $0.1 }
        rawCount = raw.count; self.stopwordCount = stopwordCount; self.shortCount = shortCount
        self.words = words; self.bigrams = bigrams; combined = words + bigrams
    }
    func terms(_ useBigrams: Bool) -> [String] { useBigrams ? combined : words }
}

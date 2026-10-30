import Foundation

struct TrieNode { var children = Array(repeating: -1, count: 26); var terminal = false }
final class Trie {
    private(set) var nodes = [TrieNode()]
    private(set) var words = 0
    @discardableResult func add(_ word: [UInt8]) -> Bool {
        var node = 0
        for letter in word { let index = Int(letter - 65); if nodes[node].children[index] == -1 { let child = nodes.count; nodes.append(TrieNode()); nodes[node].children[index] = child }; node = nodes[node].children[index] }
        if nodes[node].terminal { return false }
        nodes[node].terminal = true; words += 1
        return true
    }
    func prefix(_ word: [UInt8]) -> Int? { var node = 0; for letter in word { node = nodes[node].children[Int(letter - 65)]; if node == -1 { return nil } }; return node }
    func contains(_ word: [UInt8]) -> Bool { prefix(word).map { nodes[$0].terminal } ?? false }
    func anagrams(_ rack: [UInt8]) -> [[UInt8]] {
        var counts = Array(repeating: 0, count: 27), result: [[UInt8]] = []
        for letter in rack { counts[letter == 63 ? 26 : Int(letter - 65)] += 1 }
        func visit(_ node: Int, _ word: [UInt8]) {
            if nodes[node].terminal { result.append(word) }
            for letter in 0..<26 where nodes[node].children[letter] != -1 {
                let tile = counts[letter] > 0 ? letter : 26
                if counts[tile] > 0 { counts[tile] -= 1; visit(nodes[node].children[letter], word + [UInt8(65 + letter)]); counts[tile] += 1 }
            }
        }
        visit(0, [])
        return result
    }
}

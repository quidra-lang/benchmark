struct Tile { let kind: Int; let red: Bool }
enum Tiles {
    static let suits = Array("mpsz")
    static func parse(_ text: String, empty: Bool = false) -> [Tile]? {
        if text == "-" && empty { return [] }
        var digits: [Int] = [], result: [Tile] = []
        for character in text {
            if let digit = character.wholeNumberValue { digits.append(digit); continue }
            guard let suit = suits.firstIndex(of: character), !digits.isEmpty else { return nil }
            for digit in digits {
                if suit == 3 {
                    guard (1...7).contains(digit) else { return nil }
                    result.append(Tile(kind: 26 + digit, red: false))
                } else { result.append(Tile(kind: 9 * suit + (digit == 0 ? 5 : digit) - 1, red: digit == 0)) }
            }
            digits.removeAll()
        }
        return digits.isEmpty && !result.isEmpty ? result : nil
    }
    static func name(_ kind: Int) -> String { kind < 27 ? "\(kind % 9 + 1)\(suits[kind / 9])" : "\(kind - 26)z" }
    static func block(_ kinds: [Int]) -> String {
        let kinds = kinds.sorted()
        return kinds.map { String($0 < 27 ? $0 % 9 + 1 : $0 - 26) }.joined() + String(kinds[0] < 27 ? suits[kinds[0] / 9] : "z")
    }
    static func counts(_ tiles: [Tile]) -> [Int] { var result = Array(repeating: 0, count: 34); for tile in tiles { result[tile.kind] += 1 }; return result }
    static func terminal(_ kind: Int) -> Bool { kind < 27 && (kind % 9 == 0 || kind % 9 == 8) }
    static func yaochuu(_ kind: Int) -> Bool { kind >= 27 || terminal(kind) }
    static func green(_ kind: Int) -> Bool { [19, 20, 21, 23, 25, 32].contains(kind) }
    static func next(_ kind: Int) -> Int { kind < 27 ? kind / 9 * 9 + (kind % 9 + 1) % 9 : kind < 31 ? 27 + (kind - 26 + 1) % 4 : 31 + (kind - 31 + 1) % 3 }
}

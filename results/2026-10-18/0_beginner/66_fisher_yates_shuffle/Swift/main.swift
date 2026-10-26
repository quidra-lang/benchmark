var deck = "SHDC".flatMap { suit in "A23456789TJQK".map { "\($0)\(suit)" } }
var state: Int64 = 2026
for i in stride(from: 51, through: 1, by: -1) {
    state = state * 48271 % 2147483647
    let j = Int(state % Int64(i + 1))
    deck.swapAt(i, j)
}
for i in stride(from: 0, to: 52, by: 13) { print(deck[i..<(i + 13)].joined(separator: " ")) }

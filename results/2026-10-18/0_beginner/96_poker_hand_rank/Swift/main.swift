import Foundation

struct Hand {
    let text: String
    let category: Int
    let sequence: [Int]
}
func evaluate(_ text: String) -> Hand {
    let cards = text.split(separator: " ").map { Array($0) }, alphabet = Array("23456789TJQKA")
    var counts = [Int:Int]()
    for card in cards { counts[alphabet.firstIndex(of: card[0])! + 2, default: 0] += 1 }
    let ranks = counts.keys.sorted(), wheel = ranks == [2,3,4,5,14]
    let straight = wheel || (ranks.count == 5 && ranks.last! - ranks.first! == 4)
    let flush = cards.allSatisfy { $0[1] == cards[0][1] }
    let largest = counts.values.max()!, pairs = counts.values.filter { $0 == 2 }.count
    let category: Int
    if straight && flush { category = 8 }
    else if largest == 4 { category = 7 }
    else if largest == 3 && pairs == 1 { category = 6 }
    else if flush { category = 5 }
    else if straight { category = 4 }
    else if largest == 3 { category = 3 }
    else if pairs == 2 { category = 2 }
    else if pairs == 1 { category = 1 }
    else { category = 0 }
    var sequence = counts.keys.sorted { counts[$0]! == counts[$1]! ? $0 > $1 : counts[$0]! > counts[$1]! }
    if wheel && straight { sequence = [5,4,3,2,1] }
    return Hand(text: text, category: category, sequence: sequence)
}
let input = ["9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",
    "3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D"]
let categories = ["high card", "one pair", "two pair", "three of a kind", "straight",
    "flush", "full house", "four of a kind", "straight flush"]
let hands = input.map(evaluate).sorted { a,b in
    if a.category != b.category { return a.category > b.category }
    for (left,right) in zip(a.sequence,b.sequence) {
        if left != right { return left > right }
    }
    return false
}
for (i,hand) in hands.enumerated() { print("\(i + 1). \(hand.text): \(categories[hand.category])") }

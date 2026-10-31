let text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door."
var counts = [String: Int]()
for word in text.lowercased().split(whereSeparator: { $0 < "a" || $0 > "z" }) {
    counts[String(word), default: 0] += 1
}
let words = counts.keys.sorted { counts[$0]! == counts[$1]! ? $0 < $1 : counts[$0]! > counts[$1]! }
for word in words.prefix(5) { print("\(word): \(counts[word]!)") }
print("distinct words: \(counts.count)")

var counts = [Int](repeating: 0, count: 26)
let sentence = "Peter Piper picked a peck of pickled peppers!"
for byte in sentence.lowercased().utf8 where byte >= 97 && byte <= 122 {
    counts[Int(byte) - 97] += 1
}
for i in counts.indices where counts[i] > 0 {
    print("\(Character(UnicodeScalar(97 + i)!)): \(counts[i])")
}

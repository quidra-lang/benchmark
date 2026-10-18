import Foundation

func fixed(_ value: Double, _ places: Int) -> String {
    var scale = 1
    for _ in 0..<places { scale *= 10 }
    let scaled = Int((abs(value) * Double(scale)).rounded(.toNearestOrAwayFromZero))
    let fraction = String(scaled % scale)
    return "\(value < 0 ? "-" : "")\(scaled / scale).\(String(repeating: "0", count: places - fraction.count))\(fraction)"
}
let words = "we planted beans and carrots in the garden behind our old house".split(separator: " ")
var longest = words[0], shortest = words[0], total = 0
for word in words {
    if word.count > longest.count { longest = word }
    if word.count < shortest.count { shortest = word }
    total += word.count
}
print("words: \(words.count)")
print("longest: \(longest)")
print("shortest: \(shortest)")
print("average length: \(fixed(Double(total) / Double(words.count), 2))")

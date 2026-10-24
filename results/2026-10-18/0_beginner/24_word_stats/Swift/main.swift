import Foundation

let words = "we planted beans and carrots in the garden behind our old house".split(separator: " ")
let longest = words.max { $0.count < $1.count }!
let shortest = words.min { $0.count < $1.count }!
let average = Double(words.reduce(0) { $0 + $1.count }) / Double(words.count)
print("words: \(words.count)")
print("longest: \(longest)")
print("shortest: \(shortest)")
print(String(format: "average length: %.2f", locale: Locale(identifier: "en_US_POSIX"), average))

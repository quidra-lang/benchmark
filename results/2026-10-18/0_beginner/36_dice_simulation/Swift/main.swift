import Foundation


var state: Int64 = 12345
var counts = [Int](repeating: 0, count: 13)
for _ in 0..<1000 {
    var sum = 0
    for _ in 0..<2 { state = state * 48271 % 2147483647; sum += Int(state % 6) + 1 }
    counts[sum] += 1
}
var best = 2
for sum in 2...12 { print("\(sum): \(counts[sum])"); if counts[sum] > counts[best] { best = sum } }
print("most frequent: \(best)")

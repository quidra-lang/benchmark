import Foundation

let values = [72, 85, 64, 90, 85, 58, 77, 85, 69, 93, 71]
let mean = Double(values.reduce(0, +)) / Double(values.count)
var squared = 0.0
for value in values {
    let difference = Double(value) - mean
    squared += difference * difference
}
let sorted = values.sorted()
let counts = Dictionary(grouping: values, by: { $0 }).mapValues { $0.count }
let mode = counts.keys.min {
    counts[$0]! == counts[$1]! ? $0 < $1 : counts[$0]! > counts[$1]!
}!
print(String(format: "mean: %.3f", locale: Locale(identifier: "en_US_POSIX"), mean))
print("median: \(sorted[values.count / 2])")
print("mode: \(mode)")
print("range: \(sorted.last! - sorted.first!)")
print(String(format: "stdev: %.3f", locale: Locale(identifier: "en_US_POSIX"), sqrt(squared / Double(values.count))))

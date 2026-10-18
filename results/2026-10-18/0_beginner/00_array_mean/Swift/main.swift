import Foundation

let values = [48, 73, 56, 91, 35, 62, 84]
let mean = Double(values.reduce(0, +)) / Double(values.count)
print(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), mean))

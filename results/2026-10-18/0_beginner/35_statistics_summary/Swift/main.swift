import Foundation

func fixed(_ value: Double, _ places: Int) -> String {
    var scale = 1
    for _ in 0..<places { scale *= 10 }
    let scaled = Int((abs(value) * Double(scale)).rounded(.toNearestOrAwayFromZero))
    let fraction = String(scaled % scale)
    return "\(value < 0 ? "-" : "")\(scaled / scale).\(String(repeating: "0", count: places - fraction.count))\(fraction)"
}
let values = [72,85,64,90,85,58,77,85,69,93,71]
let mean = Double(values.reduce(0,+)) / Double(values.count)
var squared = 0.0
for value in values { let difference = Double(value) - mean; squared += difference * difference }
let sorted = values.sorted()
var counts = [Int:Int]()
for value in values { counts[value, default: 0] += 1 }
var mode = sorted[0], bestCount = 0
for value in counts.keys.sorted() { if counts[value]! > bestCount { mode = value; bestCount = counts[value]! } }
print("mean: \(fixed(mean, 3))")
print("median: \(sorted[values.count / 2])")
print("mode: \(mode)")
print("range: \(sorted.last! - sorted.first!)")
print("stdev: \(fixed(sqrt(squared / Double(values.count)), 3))")

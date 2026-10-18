import Foundation

func fixed(_ value: Double, _ places: Int) -> String {
    var scale = 1
    for _ in 0..<places { scale *= 10 }
    let scaled = Int((abs(value) * Double(scale)).rounded(.toNearestOrAwayFromZero))
    let fraction = String(scaled % scale)
    return "\(value < 0 ? "-" : "")\(scaled / scale).\(String(repeating: "0", count: places - fraction.count))\(fraction)"
}
let points = [(12,-7),(-33,25),(41,18),(-8,-44),(27,39),(-46,-12),(5,14),(36,-29),(-19,47),(-2,3)]
var minimum = Int.max, maximum = -1, minI = 0, minJ = 0, maxI = 0, maxJ = 0
for i in points.indices { for j in (i + 1)..<points.count {
    let dx = points[i].0 - points[j].0, dy = points[i].1 - points[j].1, distance = dx * dx + dy * dy
    if distance < minimum { minimum = distance; minI = i; minJ = j }
    if distance > maximum { maximum = distance; maxI = i; maxJ = j }
} }
print("closest: P\(minI) P\(minJ) \(fixed(sqrt(Double(minimum)),4))")
print("farthest: P\(maxI) P\(maxJ) \(fixed(sqrt(Double(maximum)),4))")

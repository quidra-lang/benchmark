import Foundation

func fixed(_ value: Double, _ places: Int) -> String {
    var scale = 1
    for _ in 0..<places { scale *= 10 }
    let scaled = Int((abs(value) * Double(scale)).rounded(.toNearestOrAwayFromZero))
    let fraction = String(scaled % scale)
    return "\(value < 0 ? "-" : "")\(scaled / scale).\(String(repeating: "0", count: places - fraction.count))\(fraction)"
}
let sales = [120, 135, 98, 143, 160, 152, 171, 149, 188, 176]
for i in 2..<sales.count {
    let average = Double(sales[i - 2] + sales[i - 1] + sales[i]) / 3
    print("day \(i + 1): \(fixed(average, 2))")
}

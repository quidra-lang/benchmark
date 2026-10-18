func fixed(_ value: Double, places: Int) -> String {
    var scale = 1
    for _ in 0..<places { scale *= 10 }
    let scaled = Int((abs(value) * Double(scale)).rounded(.toNearestOrAwayFromZero))
    let fraction = String(scaled % scale)
    let sign = value < 0 ? "-" : ""
    return "\(sign)\(scaled / scale).\(String(repeating: "0", count: places - fraction.count))\(fraction)"
}

let values = [48, 73, 56, 91, 35, 62, 84]
let mean = Double(values.reduce(0, +)) / Double(values.count)
print(fixed(mean, places: 2))

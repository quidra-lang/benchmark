func fixed(_ value: Double, places: Int) -> String {
    var scale = 1
    for _ in 0..<places { scale *= 10 }
    let scaled = Int((abs(value) * Double(scale)).rounded(.toNearestOrAwayFromZero))
    let fraction = String(scaled % scale)
    let sign = value < 0 ? "-" : ""
    return "\(sign)\(scaled / scale).\(String(repeating: "0", count: places - fraction.count))\(fraction)"
}

let temperatures = [-40, -15, -3, 0, 22, 37, 100]
for celsius in temperatures {
    let fahrenheit = Double(celsius) * 9 / 5 + 32
    print("\(celsius) C = \(fixed(fahrenheit, places: 1)) F")
}

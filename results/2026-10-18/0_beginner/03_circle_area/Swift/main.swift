func fixed(_ value: Double, places: Int) -> String {
    var scale = 1
    for _ in 0..<places { scale *= 10 }
    let scaled = Int((abs(value) * Double(scale)).rounded(.toNearestOrAwayFromZero))
    let fraction = String(scaled % scale)
    let sign = value < 0 ? "-" : ""
    return "\(sign)\(scaled / scale).\(String(repeating: "0", count: places - fraction.count))\(fraction)"
}

let radii = [3, 7, 12, 25, 41]
let pi = 3.141592653589793
for radius in radii {
    let r = Double(radius)
    let area = pi * r * r
    let circumference = 2 * pi * r
    print("r=\(radius) area=\(fixed(area, places: 3)) circumference=\(fixed(circumference, places: 3))")
}

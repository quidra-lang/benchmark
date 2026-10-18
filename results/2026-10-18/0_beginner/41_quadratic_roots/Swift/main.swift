import Foundation

func fixed(_ value: Double, _ places: Int) -> String {
    var scale = 1
    for _ in 0..<places { scale *= 10 }
    let scaled = Int((abs(value) * Double(scale)).rounded(.toNearestOrAwayFromZero))
    let fraction = String(scaled % scale)
    return "\(value < 0 ? "-" : "")\(scaled / scale).\(String(repeating: "0", count: places - fraction.count))\(fraction)"
}
for (a,b,c) in [(1,-3,-10),(-2,5,4),(3,1,-2),(4,-12,9),(1,2,5),(-2,3,-4)] {
    let d = b * b - 4 * a * c, prefix = "\(a) \(b) \(c): "
    if d > 0 {
        let first = (Double(-b) + sqrt(Double(d))) / Double(2 * a)
        let second = (Double(-b) - sqrt(Double(d))) / Double(2 * a)
        print(prefix + "x1 = \(fixed(max(first,second),4)), x2 = \(fixed(min(first,second),4))")
    } else if d == 0 { print(prefix + "x = \(fixed(Double(-b) / Double(2 * a),4))") }
    else {
        let p = fixed(Double(-b) / Double(2 * a),4), q = fixed(sqrt(Double(-d)) / Double(2 * abs(a)),4)
        print(prefix + "x = \(p) + \(q)i, \(p) - \(q)i")
    }
}

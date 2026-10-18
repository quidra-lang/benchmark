import Foundation

func fixed(_ value: Double, _ places: Int) -> String {
    var scale = 1
    for _ in 0..<places { scale *= 10 }
    let scaled = Int((abs(value) * Double(scale)).rounded(.toNearestOrAwayFromZero))
    let fraction = String(scaled % scale)
    return "\(value < 0 ? "-" : "")\(scaled / scale).\(String(repeating: "0", count: places - fraction.count))\(fraction)"
}

typealias Point = (x: Int, y: Int)
func cross(_ o: Point, _ a: Point, _ b: Point) -> Int {
    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
}
func chain(_ points: [Point]) -> [Point] {
    var result = [Point]()
    for point in points {
        while result.count >= 2 && cross(result[result.count - 2],result.last!,point) <= 0 {
            result.removeLast()
        }
        result.append(point)
    }
    return result
}
let input: [Point] = [(3,2), (-6,1), (8,4), (0,0), (-3,7), (4,-3), (1,-5), (-2,1), (5,6), (-6,-2), (2,-2), (7,-1), (-3,4), (2,8), (-6,3)]
let points = input.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
var lower = chain(points), upper = chain(Array(points.reversed()))
lower.removeLast()
upper.removeLast()
lower.append(contentsOf: upper)
var crossSum = 0
print("hull: \(lower.count) points")
for i in lower.indices {
    let a = lower[i], b = lower[(i + 1) % lower.count]
    print("(\(a.x), \(a.y))")
    crossSum += a.x * b.y - b.x * a.y
}
print("area: \(fixed(Double(crossSum) / 2,1))")

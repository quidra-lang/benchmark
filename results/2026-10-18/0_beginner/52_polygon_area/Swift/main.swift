import Foundation

func fixed(_ value: Double, _ places: Int) -> String {
    var scale = 1
    for _ in 0..<places { scale *= 10 }
    let scaled = Int((abs(value) * Double(scale)).rounded(.toNearestOrAwayFromZero))
    let fraction = String(scaled % scale)
    return "\(value < 0 ? "-" : "")\(scaled / scale).\(String(repeating: "0", count: places - fraction.count))\(fraction)"
}
let polygons = [[(0,0),(5,0),(6,4),(1,3)],[(2,1),(0,4),(3,7),(7,6),(8,2)],[(0,0),(8,0),(8,6),(5,6),(4,3),(3,6),(0,6)]]
for (k,vertices) in polygons.enumerated() {
    var cross = 0, perimeter = 0.0
    for i in vertices.indices { let (x,y) = vertices[i], (nx,ny) = vertices[(i + 1) % vertices.count]; cross += x * ny - nx * y; let dx = x - nx, dy = y - ny; perimeter += sqrt(Double(dx * dx + dy * dy)) }
    print("polygon \(k + 1): area=\(fixed(Double(abs(cross)) / 2,1)) perimeter=\(fixed(perimeter,3))")
}

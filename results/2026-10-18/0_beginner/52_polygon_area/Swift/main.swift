import Foundation

let polygons = [[(0,0),(5,0),(6,4),(1,3)],[(2,1),(0,4),(3,7),(7,6),(8,2)],[(0,0),(8,0),(8,6),(5,6),(4,3),(3,6),(0,6)]]
for (k,vertices) in polygons.enumerated() {
    var cross = 0, perimeter = 0.0
    for i in vertices.indices {
        let (x,y) = vertices[i], (nx,ny) = vertices[(i + 1) % vertices.count]
        cross += x * ny - nx * y
        let dx = x - nx, dy = y - ny
        perimeter += sqrt(Double(dx * dx + dy * dy))
    }
    print(String(format: "polygon %d: area=%.1f perimeter=%.3f", locale: Locale(identifier: "en_US_POSIX"), k + 1, Double(abs(cross)) / 2, perimeter))
}

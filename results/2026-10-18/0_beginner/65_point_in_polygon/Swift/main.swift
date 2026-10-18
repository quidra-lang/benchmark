import Foundation


let polygon = [(1,1),(11,2),(13,9),(9,7),(7,12),(5,6),(2,10),(3,5)]
for (px,py) in [(4,8),(6,4),(10,8),(7,11),(14,3),(12,8)] {
    var inside = false
    for i in polygon.indices {
        let (x1,y1) = polygon[i], (x2,y2) = polygon[(i + 1) % polygon.count]
        if (y1 > py) != (y2 > py) {
            let intersection = Double(x1) + Double((x2 - x1) * (py - y1)) / Double(y2 - y1)
            if intersection > Double(px) { inside.toggle() }
        }
    }
    print("(\(px), \(py)): \(inside ? "inside" : "outside")")
}

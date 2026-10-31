func bresenham(_ start: Point, _ end: Point) -> [Point] {
    var x = start.x, y = start.y, error = abs(end.x - start.x) - abs(end.y - start.y)
    let dx = abs(end.x - start.x), dy = -abs(end.y - start.y), sx = start.x < end.x ? 1 : -1, sy = start.y < end.y ? 1 : -1
    var points: [Point] = []
    while true { points.append(Point(x: x, y: y)); if x == end.x && y == end.y { return points }; let doubled = 2 * error; if doubled >= dy { error += dy; x += sx }; if doubled <= dx { error += dx; y += sy } }
}
func expandSquare(_ point: Point, _ width: Int) -> [Point] { let low = -((width - 1) / 2); return (low..<(low + width)).flatMap { y in (low..<(low + width)).map { Point(x: point.x + $0, y: point.y + y) } } }
func circlePoints(_ radius: Int) -> Set<Point> {
    var result: Set<Point> = [], a = radius, b = 0, error = 1 - radius
    while a >= b { for (x, y) in [(a, b), (b, a), (-b, a), (-a, b), (-a, -b), (-b, -a), (b, -a), (a, -b)] { result.insert(Point(x: x, y: y)) }; b += 1; if error < 0 { error += 2 * b + 1 } else { a -= 1; error += 2 * (b - a) + 1 } }
    return result
}
func ellipsePoints(_ rx: Int, _ ry: Int) -> Set<Point> {
    let rx2 = rx * rx, ry2 = ry * ry
    var x = 0, y = ry, points: Set<Point> = [Point(x: 0, y: ry), Point(x: 0, y: -ry)]
    func appendQuadrants() { for (a, b) in [(x, y), (-x, y), (x, -y), (-x, -y)] { points.insert(Point(x: a, y: b)) } }
    while ry2 * x < rx2 * y { let decision = 4 * ry2 * (x + 1) * (x + 1) + rx2 * (2 * y - 1) * (2 * y - 1) - 4 * rx2 * ry2; x += 1; if decision >= 0 { y -= 1 }; appendQuadrants() }
    while y > 0 { let decision = ry2 * (2 * x + 1) * (2 * x + 1) + 4 * rx2 * (y - 1) * (y - 1) - 4 * rx2 * ry2; y -= 1; if decision <= 0 { x += 1 }; appendQuadrants() }
    return points
}
func bezierPoints(_ controls: [Point], _ segments: Int) -> [Point] {
    let degree = controls.count - 1, scale = degree == 2 ? segments * segments : segments * segments * segments
    return (0...segments).map { index in
        let rest = segments - index, weights = degree == 2 ? [rest * rest, 2 * index * rest, index * index] : [rest * rest * rest, 3 * index * rest * rest, 3 * index * index * rest, index * index * index]
        return Point(x: roundRatio(zip(weights, controls).reduce(0) { $0 + $1.0 * $1.1.x }, scale), y: roundRatio(zip(weights, controls).reduce(0) { $0 + $1.0 * $1.1.y }, scale))
    }
}

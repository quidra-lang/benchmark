func fillPolygons(_ sequences: [[Point]], _ rule: String, _ clip: Rectangle) -> Set<Point> {
    let edges = sequences.flatMap { vertices in vertices.enumerated().compactMap { index, start -> (Point, Point)? in let end = vertices[(index + 1) % vertices.count]; return start.y == end.y ? nil : (start, end) } }
    var pixels: Set<Point> = []
    for y in clip.y0...clip.y1 {
        let crossings = edges.compactMap { a, b -> (Int, Int)? in
            if y < min(a.y, b.y) || y >= max(a.y, b.y) { return nil }
            var d = b.y - a.y, n = 2 * a.x * (b.y - a.y) + (2 * y + 1 - 2 * a.y) * (b.x - a.x)
            if d < 0 { d = -d; n = -n }
            return (floorDivide(n - d, 2 * d) + 1, b.y > a.y ? 1 : -1)
        }.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        var count = 0, winding = 0, index = 0
        for x in clip.x0...clip.x1 { while index < crossings.count && crossings[index].0 <= x { count += 1; winding += crossings[index].1; index += 1 }; if rule == "evenodd" ? count % 2 == 1 : winding != 0 { pixels.insert(Point(x: x, y: y)) } }
    }
    return pixels
}
func fillShape(_ center: Point, _ points: Set<Point>, _ clip: Rectangle) -> Set<Point> {
    var extents: [Int: Int] = [:], pixels: Set<Point> = []
    for point in points { extents[point.y] = max(extents[point.y] ?? 0, abs(point.x)) }
    for (dy, extent) in extents { let y = center.y + dy, low = max(clip.x0, center.x - extent), high = min(clip.x1, center.x + extent); if y >= clip.y0 && y <= clip.y1 && low <= high { for x in low...high { pixels.insert(Point(x: x, y: y)) } } }
    return pixels
}
func floodFill(_ layer: Layer, _ seed: Point, _ clip: Rectangle) -> Set<Point> {
    let target = layer.colorAt(seed)
    var pixels: Set<Point> = [seed], pending = [seed]
    while let point = pending.popLast() { for neighbor in [Point(x: point.x + 1, y: point.y), Point(x: point.x - 1, y: point.y), Point(x: point.x, y: point.y + 1), Point(x: point.x, y: point.y - 1)] where clip.contains(neighbor) && !pixels.contains(neighbor) && layer.colorAt(neighbor) == target { pixels.insert(neighbor); pending.append(neighbor) } }
    return pixels
}

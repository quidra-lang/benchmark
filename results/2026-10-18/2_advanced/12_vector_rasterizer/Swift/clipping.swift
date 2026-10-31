func regionCode(_ point: Point, _ clip: Rectangle) -> Int { (point.x < clip.x0 ? 1 : 0) | (point.x > clip.x1 ? 2 : 0) | (point.y < clip.y0 ? 4 : 0) | (point.y > clip.y1 ? 8 : 0) }
func clipSegment(_ start: Point, _ end: Point, _ clip: Rectangle) -> (Point, Point)? {
    var p = start, q = end
    while true {
        let first = regionCode(p, clip), second = regionCode(q, clip)
        if first == 0 && second == 0 { return (p, q) }
        if first & second != 0 { return nil }
        let code = first != 0 ? first : second, a = first != 0 ? p : q, b = first != 0 ? q : p
        let point: Point
        if code & 4 != 0 { point = Point(x: a.x + roundRatio((b.x - a.x) * (clip.y0 - a.y), b.y - a.y), y: clip.y0) }
        else if code & 8 != 0 { point = Point(x: a.x + roundRatio((b.x - a.x) * (clip.y1 - a.y), b.y - a.y), y: clip.y1) }
        else if code & 2 != 0 { point = Point(x: clip.x1, y: a.y + roundRatio((b.y - a.y) * (clip.x1 - a.x), b.x - a.x)) }
        else { point = Point(x: clip.x0, y: a.y + roundRatio((b.y - a.y) * (clip.x0 - a.x), b.x - a.x)) }
        if first != 0 { p = point } else { q = point }
    }
}
func clipPolygon(_ vertices: [Point], _ clip: Rectangle) -> [Point] {
    var current = vertices
    for (axis, limit, minimum) in [(0, clip.x0, true), (0, clip.x1 + 1, false), (1, clip.y0, true), (1, clip.y1 + 1, false)] {
        func inside(_ point: Point) -> Bool { let value = axis == 0 ? point.x : point.y; return minimum ? value >= limit : value <= limit }
        func intersection(_ start: Point, _ end: Point) -> Point { axis == 0 ? Point(x: limit, y: start.y + roundRatio((limit - start.x) * (end.y - start.y), end.x - start.x)) : Point(x: start.x + roundRatio((limit - start.y) * (end.x - start.x), end.y - start.y), y: limit) }
        var output: [Point] = []
        for (index, end) in current.enumerated() { let start = current[(index + current.count - 1) % current.count]; if inside(end) { if !inside(start) { output.append(intersection(start, end)) }; output.append(end) } else if inside(start) { output.append(intersection(start, end)) } }
        current = output
    }
    return current
}

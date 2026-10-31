struct Point: Hashable, Comparable {
    let x: Int
    let y: Int
    init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
    static func < (first: Point, second: Point) -> Bool { first.x == second.x ? first.y < second.y : first.x < second.x }
}

typealias Mask = [[Bool]]
let neighborhood = [Point(0, -1), Point(1, -1), Point(1, 0), Point(1, 1), Point(0, 1), Point(-1, 1), Point(-1, 0), Point(-1, -1)]

func occupied(_ mask: Mask, _ x: Int, _ y: Int) -> Bool {
    y >= 0 && y < mask.count && x >= 0 && x < mask[0].count && mask[y][x]
}

func erode(_ mask: Mask, _ offsets: [Point]) -> Mask {
    mask.enumerated().map { y, row in row.indices.map { x in offsets.allSatisfy { occupied(mask, x + $0.x, y + $0.y) } } }
}
func dilate(_ mask: Mask, _ offsets: [Point]) -> Mask {
    mask.enumerated().map { y, row in row.indices.map { x in offsets.contains { occupied(mask, x - $0.x, y - $0.y) } } }
}
func opening(_ mask: Mask, _ offsets: [Point]) -> Mask { dilate(erode(mask, offsets), offsets) }
func closing(_ mask: Mask, _ offsets: [Point]) -> Mask { erode(dilate(mask, offsets), offsets) }

private func neighborBits(_ pixels: Set<Point>, _ point: Point) -> [Bool] {
    neighborhood.map { pixels.contains(Point(point.x + $0.x, point.y + $0.y)) }
}
private func transitions(_ bits: [Bool]) -> Int { (0..<8).filter { !bits[$0] && bits[($0 + 1) % 8] }.count }
func crossingNumber(_ pixels: Set<Point>, _ point: Point) -> Int { transitions(neighborBits(pixels, point)) }

private func removable(_ bits: [Bool], _ first: Bool) -> Bool {
    let count = bits.filter { $0 }.count
    if count < 2 || count > 6 || transitions(bits) != 1 { return false }
    let (p2, p4, p6, p8) = (bits[0], bits[2], bits[4], bits[6])
    return first ? !(p2 && p4 && p6) && !(p4 && p6 && p8) : !(p2 && p4 && p8) && !(p2 && p6 && p8)
}
private func thinningStep(_ pixels: inout Set<Point>, _ first: Bool) -> Bool {
    let removed = pixels.filter { removable(neighborBits(pixels, $0), first) }
    pixels.subtract(removed)
    return !removed.isEmpty
}
func thin(_ pixels: [Point]) -> Set<Point> {
    var skeleton = Set(pixels)
    while true {
        let first = thinningStep(&skeleton, true)
        let second = thinningStep(&skeleton, false)
        if !first && !second { return skeleton }
    }
}

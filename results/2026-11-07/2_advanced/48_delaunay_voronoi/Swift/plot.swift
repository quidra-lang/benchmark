import Foundation

struct Canvas {
    let width: Int
    let height: Int
    var rows: [[Character]]

    init(_ width: Int, _ height: Int) { self.width = width; self.height = height; rows = Array(repeating: Array(repeating: " ", count: width), count: height) }
    func position(_ center: Center) -> (column: Int, row: Int) {
        ((2 * center.x * (width - 1) + 1000 * center.denominator) / (2000 * center.denominator),
         height - 1 - (2 * center.y * (height - 1) + 1000 * center.denominator) / (2000 * center.denominator))
    }
    func position(_ point: Point) -> (column: Int, row: Int) { position(Center(x: point.x, y: point.y, denominator: 1)) }
    mutating func mark(_ point: Point, _ character: Character) { let cell = position(point); rows[cell.row][cell.column] = character }
    mutating func mark(_ center: Center, _ character: Character) { let cell = position(center); rows[cell.row][cell.column] = character }

    mutating func line(_ first: Point, _ second: Point, _ character: Character) {
        let start = position(first), end = position(second)
        var x = start.column, y = start.row
        let dx = abs(end.column - x), dy = -abs(end.row - y), sx = x < end.column ? 1 : -1, sy = y < end.row ? 1 : -1
        var error = dx + dy
        while true {
            rows[y][x] = character
            if x == end.column && y == end.row { break }
            let twiceError = 2 * error
            if twiceError >= dy { error += dy; x += sx }
            if twiceError <= dx { error += dx; y += sy }
        }
    }

    mutating func drawVoronoi(_ points: [Point]) {
        let horizontal = width - 1, vertical = height - 1
        var owners = Array(repeating: Array(repeating: 0, count: width), count: height)
        for row in 0..<height {
            for column in 0..<width {
                var best = Int.max
                for site in 1..<points.count {
                    let dx = (column * 1000 - points[site].x * horizontal) * vertical
                    let dy = ((vertical - row) * 1000 - points[site].y * vertical) * horizontal
                    let distance = dx * dx + dy * dy
                    if distance < best { owners[row][column] = site; best = distance }
                }
            }
        }
        for row in 0..<height {
            for column in 0..<width {
                let owner = owners[row][column]
                if (column < horizontal && owner != owners[row][column + 1]) || (row < vertical && owner != owners[row + 1][column]) { rows[row][column] = "#" }
            }
        }
        for point in points.dropFirst() { mark(point, "o") }
    }

    func framed() -> [String] {
        let border = "+" + String(repeating: "-", count: width) + "+"
        return [border] + rows.map { "|" + String($0) + "|" } + [border]
    }
}

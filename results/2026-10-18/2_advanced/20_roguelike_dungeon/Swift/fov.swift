let directionNames = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
let directions = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]
func passable(_ level: Level, _ x: Int, _ y: Int) -> Bool {
    x >= 0 && x < level.width && y >= 0 && y < level.height && [UInt8(46), 35, 43, 60, 62].contains(level.terrain[y][x])
}
func canMove(_ level: Level, _ x: Int, _ y: Int, _ dx: Int, _ dy: Int) -> Bool {
    passable(level, x + dx, y + dy) && (dx == 0 || dy == 0 || (level.terrain[y][x] != 43 && level.terrain[y + dy][x + dx] != 43))
}
func lineCells(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> [Cell] {
    let dx = abs(x1 - x0)
    let dy = abs(y1 - y0)
    let sx = x1 > x0 ? 1 : -1
    let sy = y1 > y0 ? 1 : -1
    var error = dx - dy
    var x = x0
    var y = y0
    var cells: [Cell] = []
    while x != x1 || y != y1 {
        let twice = 2 * error
        if twice > -dy { error -= dy; x += sx }
        if twice < dx { error += dx; y += sy }
        cells.append(Cell(x: x, y: y))
    }
    return cells
}
func fieldOfView(_ level: Level, _ px: Int, _ py: Int, _ radius: Int) -> [[Bool]] {
    var visible = Array(repeating: Array(repeating: false, count: level.width), count: level.height)
    for y in max(0, py - radius)..<min(level.height, py + radius + 1) {
        for x in max(0, px - radius)..<min(level.width, px + radius + 1) {
            if (x - px) * (x - px) + (y - py) * (y - py) > radius * radius { continue }
            if lineCells(px, py, x, y).dropLast().allSatisfy({ passable(level, $0.x, $0.y) }) { visible[y][x] = true }
        }
    }
    return visible
}
func distances(_ level: Level, _ px: Int, _ py: Int) -> [[Int?]] {
    var distance = Array(repeating: Array<Int?>(repeating: nil, count: level.width), count: level.height)
    distance[py][px] = 0
    var queue = [Cell(x: px, y: py)]
    var head = 0
    while head < queue.count {
        let cell = queue[head]; head += 1
        for (dx, dy) in directions {
            let x = cell.x + dx
            let y = cell.y + dy
            if canMove(level, cell.x, cell.y, dx, dy) && distance[y][x] == nil {
                distance[y][x] = distance[cell.y][cell.x]! + 1
                queue.append(Cell(x: x, y: y))
            }
        }
    }
    return distance
}

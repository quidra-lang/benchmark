let directions = [Cell(x: 0, y: -1), Cell(x: 1, y: 0), Cell(x: 0, y: 1), Cell(x: -1, y: 0)]
func neighbor(_ cell: Cell, _ direction: Int) -> Cell { Cell(x: cell.x + directions[direction].x, y: cell.y + directions[direction].y) }
struct DistanceField {
    let distances: [[Int?]]
    let exit: Cell
    let width: Int
    let height: Int
    init(_ grid: GridMap, _ towers: Set<Cell>) {
        var distances = Array(repeating: Array<Int?>(repeating: nil, count: grid.width), count: grid.height)
        distances[grid.exit.y][grid.exit.x] = 0
        var queue = [grid.exit], head = 0
        while head < queue.count {
            let cell = queue[head]; head += 1
            for direction in directions.indices {
                let next = neighbor(cell, direction)
                if grid.inside(next) && !grid.isRock(next) && !towers.contains(next) && distances[next.y][next.x] == nil {
                    distances[next.y][next.x] = distances[cell.y][cell.x]! + 1; queue.append(next)
                }
            }
        }
        self.distances = distances; exit = grid.exit; width = grid.width; height = grid.height
    }
    func at(_ cell: Cell) -> Int? { distances[cell.y][cell.x] }
    func direction(_ cell: Cell) -> Int {
        var best: Int? = nil, bestDistance = 0
        for direction in directions.indices {
            let next = neighbor(cell, direction)
            if next.x < 0 || next.y < 0 || next.x >= width || next.y >= height { continue }
            if let distance = at(next), best == nil || distance < bestDistance { best = direction; bestDistance = distance }
        }
        return best!
    }
    func nextCell(_ cell: Cell) -> Cell { neighbor(cell, direction(cell)) }
    func path(_ start: Cell) -> [Cell] { var cells = [start]; while cells.last! != exit { cells.append(nextCell(cells.last!)) }; return cells }
}

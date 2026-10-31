import Foundation
struct Cell: Hashable, Comparable {
    let x: Int, y: Int
    static func < (a: Self, b: Self) -> Bool {
        a.x == b.x ? a.y < b.y : a.x < b.x
    }
}
typealias Path = [Cell]
struct Agent {
    let start: Cell;
    let goal: Cell
}
final class Grid {
    let width: Int, height: Int, rows: [[Character]], agents: [Agent]
    var distances: [[Cell: Int]] = []
    init() {
        let lines = try! String(contentsOfFile: "input/map.txt", encoding: .ascii).split(separator: "\n"), dimensions = lines[0].split(separator: " ").map {
            Int($0)!
        }
        width = dimensions[0];
        height = dimensions[1];
        rows = lines.dropFirst().map(Array.init)
        agents = try! String(contentsOfFile: "input/agents.csv", encoding: .ascii).split(separator: "\n").dropFirst().map {
            line in let w = line.split(separator: ",").map {
                Int($0)!
            }
            return Agent(start: Cell(x: w[1], y: w[2]), goal: Cell(x: w[3], y: w[4]))
        }
        distances = agents.map {
            distance($0.goal)
        }
    }
    func free(_ cell: Cell) -> Bool {
        cell.x >= 0 && cell.x < width && cell.y >= 0 && cell.y < height && rows[cell.y][cell.x] == "."
    }
    func destinations(_ cell: Cell) -> [Cell] {
        [(0,0),(0,-1),(1,0),(0,1),(-1,0)].map {
            Cell(x: cell.x + $0.0, y: cell.y + $0.1)
        }.filter(free)
    }
    func cells() -> [Cell] {
        (0..<height).flatMap {
            y in (0..<width).map {
                Cell(x: $0, y: y)
            }.filter(free)
        }
    }
    func distance(_ goal: Cell) -> [Cell: Int] {
        var queue = [goal], head = 0, result = [goal: 0]
        while head < queue.count {
            let cell = queue[head];
            head += 1;
            for next in destinations(cell).dropFirst() where result[next] == nil {
                result[next] = result[cell]! + 1;
                queue.append(next)
            }
        }
        return result
    }
}

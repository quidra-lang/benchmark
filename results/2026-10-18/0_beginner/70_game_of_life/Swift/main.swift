import Foundation


let initial = [".#......", "..#.....", "###.....", "........",
    "........", "........", ".....###", "........"]
var board = initial.map { $0.map { $0 == "#" } }
for generation in 0...4 {
    print("generation \(generation)")
    for row in board { print(row.map { $0 ? "#" : "." }.joined()) }
    if generation == 4 { break }
    var next = [[Bool]](repeating: [Bool](repeating: false, count: 8), count: 8)
    for r in 0..<8 {
        for c in 0..<8 {
            var neighbors = 0
            for dr in -1...1 {
                for dc in -1...1 {
                    if dr == 0 && dc == 0 { continue }
                    let nr = r + dr, nc = c + dc
                    if nr >= 0 && nr < 8 && nc >= 0 && nc < 8 && board[nr][nc] { neighbors += 1 }
                }
            }
            next[r][c] = neighbors == 3 || (board[r][c] && neighbors == 2)
        }
    }
    board = next
}
let alive = board.reduce(0) { $0 + $1.filter { $0 }.count }
print("alive: \(alive)")

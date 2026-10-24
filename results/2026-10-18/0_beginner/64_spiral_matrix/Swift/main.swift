import Foundation

var matrix = [[Int]](repeating: [Int](repeating: 0, count: 6), count: 5)
let dr = [0,1,0,-1], dc = [1,0,-1,0]
var r = 0, c = 0, direction = 0
for value in 1...30 {
    matrix[r][c] = value
    if value == 30 { break }
    let nr = r + dr[direction], nc = c + dc[direction]
    if nr < 0 || nr >= 5 || nc < 0 || nc >= 6 || matrix[nr][nc] != 0 { direction = (direction + 1) % 4 }
    r += dr[direction]
    c += dc[direction]
}
for row in matrix {
    print(row.map { String(format: "%3d", locale: Locale(identifier: "en_US_POSIX"), $0) }.joined())
}

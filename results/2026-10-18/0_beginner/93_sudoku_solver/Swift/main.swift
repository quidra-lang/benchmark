@discardableResult
func solve(_ board: inout [[Int]], _ placements: inout Int64) -> Bool {
    for r in 0..<9 {
        for c in 0..<9 {
            if board[r][c] != 0 { continue }
            for digit in 1...9 {
                let valid = (0..<9).allSatisfy { i in
                    board[r][i] != digit && board[i][c] != digit &&
                        board[r / 3 * 3 + i / 3][c / 3 * 3 + i % 3] != digit
                }
                if !valid { continue }
                board[r][c] = digit
                placements += 1
                if solve(&board,&placements) { return true }
                board[r][c] = 0
            }
            return false
        }
    }
    return true
}
let rows = ["800025000", "070080005", "260400070", "000001900", "010000040",
    "600200000", "900010000", "700000004", "020000036"]
var board = rows.map { row in row.utf8.map { Int($0) - 48 } }
var placements: Int64 = 0
solve(&board,&placements)
for row in board { print(row.map(String.init).joined(separator: " ")) }
print("placements: \(placements)")

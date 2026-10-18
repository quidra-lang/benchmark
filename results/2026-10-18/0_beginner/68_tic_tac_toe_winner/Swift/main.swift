import Foundation


let boards = [["XXX","OO.","O.X"],["X.O",".X.","O.."],["XO.",".OX","XO."],
    ["XOX","XOO","OXX"],["X.O","XO.","O.X"],["XOX","OXO","OXX"]]
let lines = [[0,1,2],[3,4,5],[6,7,8],[0,3,6],[1,4,7],[2,5,8],[0,4,8],[2,4,6]]
for (i,board) in boards.enumerated() {
    let cells = Array(board.joined())
    var result = cells.contains(".") ? "in progress" : "draw"
    for line in lines {
        let mark = cells[line[0]]
        if mark != "." && mark == cells[line[1]] && mark == cells[line[2]] {
            result = "\(mark) wins"
            break
        }
    }
    print("board \(i + 1): \(result)")
}

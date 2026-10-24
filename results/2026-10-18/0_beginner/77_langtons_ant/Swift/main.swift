var black = [[Bool]](repeating: [Bool](repeating: false, count: 11), count: 11)
var r = 5, c = 5, direction = 0
let dr = [-1,0,1,0], dc = [0,1,0,-1]
for _ in 0..<300 {
    direction = (direction + (black[r][c] ? 3 : 1)) % 4
    black[r][c].toggle()
    r = (r + dr[direction] + 11) % 11
    c = (c + dc[direction] + 11) % 11
}
for row in 0..<11 {
    var line = ""
    for column in 0..<11 {
        line += row == r && column == c ? "A" : black[row][column] ? "#" : "."
    }
    print(line)
}
print("black: \(black.joined().filter { $0 }.count)")

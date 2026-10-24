let rows = ["#############",
    "#S..#.......#",
    "#.#.#.###.#.#",
    "#.#...#...#.#",
    "#.###.#.###.#",
    "#...#...#...#",
    "###.#####.#.#",
    "#.......#..G#",
    "#############"]
var maze = rows.map { Array($0) }, start = -1, goal = -1
for r in 0..<9 {
    for c in 0..<13 {
        if maze[r][c] == "S" { start = r * 13 + c }
        if maze[r][c] == "G" { goal = r * 13 + c }
    }
}
var parent = [Int](repeating: -1, count: 117), queue = [start], head = 0
parent[start] = start
let dr = [-1,1,0,0], dc = [0,0,-1,1]
while head < queue.count {
    let cell = queue[head], r = cell / 13, c = cell % 13
    head += 1
    if cell == goal { break }
    for d in 0..<4 {
        let nr = r + dr[d], nc = c + dc[d]
        if nr < 0 || nr >= 9 || nc < 0 || nc >= 13 { continue }
        let next = nr * 13 + nc
        if maze[nr][nc] != "#" && parent[next] < 0 {
            parent[next] = cell
            queue.append(next)
        }
    }
}
var steps = 0, cell = goal
while cell != start {
    if cell != goal { maze[cell / 13][cell % 13] = "*" }
    steps += 1
    cell = parent[cell]
}
print("steps: \(steps)")
for row in maze { print(String(row)) }

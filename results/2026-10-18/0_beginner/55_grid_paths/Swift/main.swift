let grid = [".......","..#....","....#..",".#.....","...#.#.","......."].map { Array($0) }
for obstacles in [false,true] {
    var dp = [[Int]](repeating: [Int](repeating: 0,count: 7),count: 6)
    dp[0][0] = 1
    for r in 0..<6 {
        for c in 0..<7 {
            if obstacles && grid[r][c] == "#" {
                dp[r][c] = 0
                continue
            }
            if r > 0 { dp[r][c] += dp[r - 1][c] }
            if c > 0 { dp[r][c] += dp[r][c - 1] }
        }
    }
    print("\(obstacles ? "with" : "without") obstacles: \(dp[5][6])")
}

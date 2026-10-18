fn main() {
    let grid = [".......", "..#....", "....#..", ".#.....", "...#.#.", "......."];
    for obstacles in [false, true] {
        let mut dp = [[0; 7]; 6];
        dp[0][0] = 1;
        for r in 0..6 {
            for c in 0..7 {
                if obstacles && grid[r].as_bytes()[c] == b'#' {
                    continue;
                }
                if r > 0 {
                    dp[r][c] += dp[r - 1][c];
                }
                if c > 0 {
                    dp[r][c] += dp[r][c - 1];
                }
            }
        }
        println!("{} obstacles: {}", if obstacles { "with" } else { "without" }, dp[5][6]);
    }
}

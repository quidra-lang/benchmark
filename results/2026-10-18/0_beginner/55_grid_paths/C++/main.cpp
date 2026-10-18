#include <iostream>
#include <string>
#include <array>

int main() {
    const std::array<std::string, 6> grid = {".......", "..#....", "....#..", ".#.....", "...#.#.",
        "......."};
    for (int obstacles = 0; obstacles < 2; obstacles++) {
        int dp[6][7] {
        };
        dp[0][0] = 1;
        for (int r = 0; r < 6; r++)
            for (int c = 0; c < 7; c++) {
                if (obstacles && grid[r][c] == '#') {
                    dp[r][c] = 0;
                    continue;
                }
                if (r)
                    dp[r][c] += dp[r - 1][c];
                if (c)
                    dp[r][c] += dp[r][c - 1];
            }
        std::cout << (obstacles ? "with" : "without") << " obstacles: " << dp[5][6] << '\n';
    }
}

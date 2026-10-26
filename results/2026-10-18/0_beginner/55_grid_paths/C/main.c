#include <stdio.h>

int main(void) {
    const char *grid[] = {".......", "..#....", "....#..", ".#.....", "...#.#.", "......."};
    for (int obstacles = 0; obstacles < 2; obstacles++) {
        int dp[6][7] = {{1}};
        for (int r = 0; r < 6; r++)
            for (int c = 0; c < 7; c++) {
                if (obstacles && grid[r][c] == '#') {
                    continue;
                }
                if (r)
                    dp[r][c] += dp[r - 1][c];
                if (c)
                    dp[r][c] += dp[r][c - 1];
            }
        printf("%s obstacles: %d\n", obstacles ? "with" : "without", dp[5][6]);
    }
    return 0;
}

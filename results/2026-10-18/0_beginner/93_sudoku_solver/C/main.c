#include <stdio.h>

int solve(int board[9][9], unsigned long long *placements) {
    int row = -1, col = -1;
    for (int r = 0; r < 9 && row < 0; r++)
        for (int c = 0; c < 9; c++)
            if (board[r][c] == 0) {
                row = r;
                col = c;
                break;
            }
    if (row < 0)
        return 1;
    for (int d = 1; d <= 9; d++) {
        int safe = 1;
        for (int k = 0; k < 9; k++)
            if (board[row][k] == d || board[k][col] == d)
                safe = 0;
        for (int r = row / 3 * 3; r < row / 3 * 3 + 3; r++)
            for (int c = col / 3 * 3; c < col / 3 * 3 + 3; c++)
                if (board[r][c] == d)
                    safe = 0;
        if (safe) {
            board[row][col] = d;
            (*placements)++;
            if (solve(board, placements))
                return 1;
            board[row][col] = 0;
        }
    }
    return 0;
}

int main(void) {
    const char *rows[] = {"800025000", "070080005", "260400070", "000001900", "010000040", "600200000",
        "900010000", "700000004", "020000036"};
    int board[9][9];
    for (int r = 0; r < 9; r++)
        for (int c = 0; c < 9; c++)
            board[r][c] = rows[r][c] - '0';
    unsigned long long placements = 0;
    solve(board, &placements);
    for (int r = 0; r < 9; r++) {
        for (int c = 0; c < 9; c++)
            printf("%s%d", c ? " ": "", board[r][c]);
        putchar('\n');
    }
    printf("placements: %llu\n", placements);
    return 0;
}

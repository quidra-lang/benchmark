#include <stdio.h>
#include <string.h>

int main(void) {
    char board[8][9] = {".#......", "..#.....", "###.....", "........", "........", "........", ".....###",
        "........"};
    for (int g = 0; g <= 4; g++) {
        printf("generation %d\n", g);
        for (int r = 0; r < 8; r++)
            puts(board[r]);
        if (g == 4)
            break;
        char next[8][9];
        for (int r = 0; r < 8; r++) {
            for (int c = 0; c < 8; c++) {
                int neighbors = 0;
                for (int dr = -1; dr <= 1; dr++)
                    for (int dc = -1; dc <= 1; dc++) {
                        int rr = r + dr, cc = c + dc;
                        if ((dr || dc) && rr >= 0 && rr < 8 && cc >= 0 && cc < 8 && board[rr][cc] == '#')
                            neighbors++;
                    }
                next[r][c] = neighbors == 3 || (board[r][c] == '#' && neighbors == 2) ? '#' : '.';
            }
            next[r][8] = 0;
        }
        memcpy(board, next, sizeof board);
    }
    int alive = 0;
    for (int r = 0; r < 8; r++)
        for (int c = 0; c < 8; c++)
            if (board[r][c] == '#')
                alive++;
    printf("alive: %d\n", alive);
    return 0;
}

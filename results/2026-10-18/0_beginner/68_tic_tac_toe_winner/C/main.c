#include <stdio.h>

int main(void) {
    const char *boards[6][3] = {{"XXX", "OO.", "O.X"}, {"X.O", ".X.", "O.."}, {"XO.", ".OX", "XO."},
        {"XOX", "XOO", "OXX"}, {"X.O", "XO.", "O.X"}, {"XOX", "OXO", "OXX"}};
    for (int k = 0; k < 6; k++) {
        char winner = 0;
        int empty = 0;
        for (int r = 0; r < 3; r++) {
            for (int c = 0; c < 3; c++)
                if (boards[k][r][c] == '.')
                    empty = 1;
            if (boards[k][r][0] != '.' && boards[k][r][0] == boards[k][r][1] && boards[k][r][1] == boards[k][r][2])
                winner = boards[k][r][0];
            if (boards[k][0][r] != '.' && boards[k][0][r] == boards[k][1][r] && boards[k][1][r] == boards[k][2][r])
                winner = boards[k][0][r];
        }
        if (boards[k][0][0] != '.' && boards[k][0][0] == boards[k][1][1] && boards[k][1][1] == boards[k][2][2])
            winner = boards[k][0][0];
        if (boards[k][0][2] != '.' && boards[k][0][2] == boards[k][1][1] && boards[k][1][1] == boards[k][2][0])
            winner = boards[k][0][2];
        printf("board %d: ", k + 1);
        if (winner)
            printf("%c wins\n", winner);
        else
            puts(empty ? "in progress": "draw");
    }
    return 0;
}

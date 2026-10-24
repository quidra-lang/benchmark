#include <stdio.h>

int main(void) {
    int matrix[5][6] = {{0}}, dr[] = {0, 1, 0, -1}, dc[] = {1, 0, -1, 0}, r = 0, c = 0, d = 0;
    for (int n = 1; n <= 30; n++) {
        matrix[r][c] = n;
        if (n == 30)
            break;
        int nr = r + dr[d], nc = c + dc[d];
        if (nr < 0 || nr >= 5 || nc < 0 || nc >= 6 || matrix[nr][nc]) {
            d = (d + 1) % 4;
            nr = r + dr[d];
            nc = c + dc[d];
        }
        r = nr;
        c = nc;
    }
    for (int i = 0; i < 5; i++) {
        for (int j = 0; j < 6; j++)
            printf("%3d", matrix[i][j]);
        putchar('\n');
    }
    return 0;
}

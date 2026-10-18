#include <stdio.h>

int main(void) {
    _Bool black[11][11] = {{0}};
    int dr[] = {-1, 0, 1, 0}, dc[] = {0, 1, 0, -1}, r = 5, c = 5, d = 0;
    for (int step = 0; step < 300; step++) {
        d = (d + (black[r][c] ? 3: 1)) % 4;
        black[r][c] = !black[r][c];
        r = (r + dr[d] + 11) % 11;
        c = (c + dc[d] + 11) % 11;
    }
    int count = 0;
    for (int i = 0; i < 11; i++) {
        for (int j = 0; j < 11; j++) {
            count += black[i][j];
            putchar(i == r && j == c ? 'A': black[i][j] ? '#': '.');
        }
        putchar('\n');
    }
    printf("black: %d\n", count);
    return 0;
}

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void search(int n, int row, int *positions, int *count, int *first) {
    if (row == n) {
        if (n == 8 && *count == 0)
            memcpy(first, positions, 8 * sizeof(int));
        (*count)++;
        return;
    }
    for (int col = 0; col < n; col++) {
        int safe = 1;
        for (int r = 0; r < row; r++)
            if (positions[r] == col || abs(positions[r] - col) == row - r) {
                safe = 0;
                break;
            }
        if (safe) {
            positions[row] = col;
            search(n, row + 1, positions, count, first);
        }
    }
}

int main(void) {
    int first[8] = {0};
    for (int n = 4; n <= 8; n++) {
        int positions[8], count = 0;
        search(n, 0, positions, &count, first);
        printf("N=%d: %d solutions\n", n, count);
    }
    for (int r = 0; r < 8; r++) {
        for (int c = 0; c < 8; c++)
            putchar(first[r] == c ? 'Q' : '.');
        putchar('\n');
    }
    return 0;
}

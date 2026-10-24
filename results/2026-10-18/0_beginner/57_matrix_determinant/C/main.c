#include <stdio.h>

int det(int a[5][5], int n) {
    if (n == 1)
        return a[0][0];
    int result = 0;
    for (int j = 0; j < n; j++) {
        int minor[5][5];
        for (int r = 1; r < n; r++) {
            int col = 0;
            for (int c = 0; c < n; c++)
                if (c != j)
                    minor[r - 1][col++] = a[r][c];
        }
        int term = a[0][j] * det(minor, n - 1);
        result += j % 2 ? - term: term;
    }
    return result;
}

int main(void) {
    int matrices[3][5][5] = {{{2, -3, 1}, {5, 4, -2}, {-1, 6, 3}}, {{3, 0, -2, 5}, {1, 4, 7, -3}, {-6,
        2, 1, 8}, {9, -5, 3, 2}}, {{4, -1, 7, 0, -3}, {2, 8, -5, 6, 1}, {-9, 3, 2, -4, 5}, {6, 0, -7, 3,
        -2}, {1, -6, 4, 9, 8}}};
    for (int k = 0; k < 3; k++) {
        int n = k + 3;
        printf("det(%dx%d) = %d\n", n, n, det(matrices[k], n));
    }
    return 0;
}

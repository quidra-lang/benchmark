#include <stdio.h>

int main(void) {
    int a[3][4] = {{3, -2, 5, 1}, {-4, 7, 0, 6}, {2, 9, -8, -3}}, b[4][2] = {{1, 4}, {-5, 2}, {6, -1},
        {0, 7}};
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 2; j++) {
            int sum = 0;
            for (int k = 0; k < 4; k++)
                sum += a[i][k] * b[k][j];
            printf("%5d", sum);
        }
        putchar('\n');
    }
    return 0;
}

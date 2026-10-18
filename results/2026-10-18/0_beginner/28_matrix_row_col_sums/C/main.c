#include <stdio.h>

int main(void) {
    int matrix[4][5] = {{125, 340, 78, 912, 456}, {603, 27, 819, 150, 384}, {0, 765, 231, 498, 62},
        {947, 113, 586, 39, 720}}, columns[5] = {0}, total = 0;
    for (int i = 0; i < 4; i++) {
        int row = 0;
        for (int j = 0; j < 5; j++) {
            printf("%6d", matrix[i][j]);
            row += matrix[i][j];
            columns[j] += matrix[i][j];
        }
        total += row;
        printf("%6d\n", row);
    }
    for (int j = 0; j < 5; j++)
        printf("%6d", columns[j]);
    printf("%6d\n", total);
    return 0;
}

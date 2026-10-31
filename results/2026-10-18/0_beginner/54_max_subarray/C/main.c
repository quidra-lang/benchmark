#include <stdio.h>

int main(void) {
    int arrays[3][15] = {{3, -5, 8, -2, 6, -9, 4, 1, -7, 5, -3, 2},
                         {-4, 7, -1, 3, -8, 10, -2, 5, -6, -2, 9, -12, 4, -1},
                         {-6, -3, 5, -1, -4, 3, -9, 2, 3, -1, 4, -5, 1, 6, -2}};
    int sizes[] = {12, 14, 15};
    for (int k = 0; k < 3; k++) {
        int current = arrays[k][0], best = current, start = 0, left = 0, right = 0;
        for (int i = 1; i < sizes[k]; i++) {
            if (current < 0) {
                current = arrays[k][i];
                start = i;
            } else {
                current += arrays[k][i];
            }
            if (current > best) {
                best = current;
                left = start;
                right = i;
            }
        }
        printf("max sum %d at [%d, %d]\n", best, left, right);
    }
    return 0;
}

#include <stdio.h>

int main(void) {
    int a[] = {27, 64, 13, 88, 41, 5, 72, 36}, total = 0;
    for (int p = 1; p <= 7; p++) {
        int swaps = 0;
        for (int j = 0; j <= 7 - p; j++)
            if (a[j] > a[j + 1]) {
                int t = a[j];
                a[j] = a[j + 1];
                a[j + 1] = t;
                swaps++;
            }
        total += swaps;
        printf("pass %d:", p);
        for (int j = 0; j < 8; j++)
            printf(" %d", a[j]);
        putchar('\n');
        if (!swaps)
            break;
    }
    printf("swaps: %d\n", total);
    return 0;
}

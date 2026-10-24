#include <stdio.h>

int main(void) {
    int row[12] = {1};
    for (int n = 0; n < 12; n++) {
        for (int k = n; k > 0; k--)
            row[k] += row[k - 1];
        for (int k = 0; k <= n; k++)
            printf("%s%d", k ? " ": "", row[k]);
        putchar('\n');
    }
    return 0;
}

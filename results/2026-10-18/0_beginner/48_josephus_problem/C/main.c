#include <stdio.h>

int main(void) {
    int cases[][2] = {{7, 3}, {10, 2}, {41, 3}};
    for (int c = 0; c < 3; c++) {
        int n = cases[c][0], k = cases[c][1];
        int people[41], len = n, index = 0, last = 0;
        for (int i = 0; i < n; i++)
            people[i] = i + 1;
        printf("n=%d k=%d:", n, k);
        while (len) {
            index = (index + k - 1) % len;
            last = people[index];
            printf(" %d", last);
            for (int i = index; i < len - 1; i++)
                people[i] = people[i + 1];
            len--;
        }
        printf("\nsurvivor: %d\n", last);
    }
    return 0;
}

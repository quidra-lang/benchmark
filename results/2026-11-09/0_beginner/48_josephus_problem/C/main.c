#include <stdio.h>

int main(void) {
    int cases[][2] = {{7, 3}, {10, 2}, {41, 3}};
    for (int c = 0; c < 3; c++) {
        int n = cases[c][0], k = cases[c][1];
        int people[41], order[41], removed = 0, len = n, index = 0;
        for (int i = 0; i < n; i++)
            people[i] = i + 1;
        printf("n=%d k=%d:", n, k);
        while (len) {
            index = (index + k - 1) % len;
            order[removed++] = people[index];
            printf(" %d", order[removed - 1]);
            for (int i = index; i < len - 1; i++)
                people[i] = people[i + 1];
            len--;
        }
        printf("\nsurvivor: %d\n", order[removed - 1]);
    }
    return 0;
}

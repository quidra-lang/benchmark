#include <stdio.h>

int main(void) {
    enum { limit = 20 };
    const char *names[] = {"tent", "stove", "lantern", "rope", "camera", "blanket", "water"};
    int weights[] = {10, 3, 2, 3, 5, 5, 6}, values[] = {120, 65, 45, 20, 90, 85, 100}, dp[8][limit + 1] = {{0}};
    for (int i = 1; i <= 7; i++)
        for (int w = 0; w <= limit; w++) {
            dp[i][w] = dp[i - 1][w];
            if (weights[i - 1] <= w) {
                int candidate = dp[i - 1][w - weights[i - 1]] + values[i - 1];
                if (candidate > dp[i][w])
                    dp[i][w] = candidate;
            }
        }
    _Bool chosen[7] = {0};
    int capacity = limit, total_weight = 0;
    for (int i = 7; i >= 1; i--)
        if (dp[i][capacity] != dp[i - 1][capacity]) {
            chosen[i - 1] = 1;
            capacity -= weights[i - 1];
            total_weight += weights[i - 1];
        }
    printf("max value: %d\ntotal weight: %d\nitems:", dp[7][limit], total_weight);
    for (int i = 0; i < 7; i++)
        if (chosen[i])
            printf(" %s", names[i]);
    putchar('\n');
    return 0;
}

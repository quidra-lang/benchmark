#include <stdio.h>

int main(void) {
    int coins[] = {1, 5, 6, 9}, targets[] = {8, 11, 15, 22, 33, 40}, minimum[41] = {0}, ways[41] = {1};
    for (int amount = 1; amount <= 40; amount++) {
        minimum[amount] = 1000;
        for (int i = 0; i < 4; i++)
            if (coins[i] <= amount && minimum[amount - coins[i]] + 1 < minimum[amount])
                minimum[amount] = minimum[amount - coins[i]] + 1;
    }
    for (int i = 0; i < 4; i++)
        for (int amount = coins[i]; amount <= 40; amount++)
            ways[amount] += ways[amount - coins[i]];
    for (int i = 0; i < 6; i++) {
        int remaining = targets[i], greedy = 0;
        for (int j = 3; j >= 0; j--) {
            greedy += remaining / coins[j];
            remaining %= coins[j];
        }
        printf("%d: min=%d greedy=%d ways=%d\n", targets[i], minimum[targets[i]], greedy, ways[targets[i]]);
    }
    return 0;
}

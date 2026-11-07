#include <stdio.h>

int main(void) {
    int deck[52];
    for (int i = 0; i < 52; i++)
        deck[i] = i;
    long long x = 2026;
    for (int i = 51; i >= 1; i--) {
        x = x * 48271 % 2147483647;
        int j = (int)(x % (i + 1)), t = deck[i];
        deck[i] = deck[j];
        deck[j] = t;
    }
    const char *ranks = "A23456789TJQK", *suits = "SHDC";
    for (int i = 0; i < 52; i++) {
        if (i % 13)
            putchar(' ');
        printf("%c%c", ranks[deck[i] % 13], suits[deck[i] / 13]);
        if (i % 13 == 12)
            putchar('\n');
    }
    return 0;
}

#include <stdio.h>

int main(void) {
    int counts[13] = {0};
    long long x = 12345;
    for (int i = 0; i < 1000; i++) {
        x = x * 48271 % 2147483647;
        int a = (int)(x % 6) + 1;
        x = x * 48271 % 2147483647;
        int b = (int)(x % 6) + 1;
        counts[a + b]++;
    }
    int best = 2;
    for (int s = 2; s <= 12; s++) {
        printf("%d: %d\n", s, counts[s]);
        if (counts[s] > counts[best])
            best = s;
    }
    printf("most frequent: %d\n", best);
    return 0;
}

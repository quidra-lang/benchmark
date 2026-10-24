#include <stdio.h>

int main(void) {
    _Bool prime[201];
    for (int n = 0; n <= 200; n++)
        prime[n] = n >= 2;
    for (int p = 2; p <= 200; p++)
        if (prime[p])
            for (int j = p * 2; j <= 200; j += p)
                prime[j] = 0;
    int count = 0;
    for (int n = 2; n <= 200; n++)
        if (prime[n])
            count++;
    printf("count: %d\n", count);
    int printed = 0;
    for (int n = 2; n <= 200; n++)
        if (prime[n]) {
            if (printed % 10)
                putchar(' ');
            printf("%d", n);
            printed++;
            if (printed % 10 == 0 || printed == count)
                putchar('\n');
        }
    return 0;
}

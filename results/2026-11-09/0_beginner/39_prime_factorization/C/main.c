#include <stdio.h>

int main(void) {
    int values[] = {84, 9973, 15625, 1001, 123456, 48000, 999958, 999999};
    for (int i = 0; i < 8; i++) {
        int n = values[i], first = 1;
        printf("%d = ", n);
        for (int d = 2; d * d <= n; d++) {
            int e = 0;
            while (n % d == 0) {
                n /= d;
                e++;
            }
            if (e) {
                if (!first)
                    printf(" * ");
                printf("%d", d);
                if (e > 1)
                    printf("^%d", e);
                first = 0;
            }
        }
        if (n > 1) {
            if (!first)
                printf(" * ");
            printf("%d", n);
        }
        putchar('\n');
    }
    return 0;
}

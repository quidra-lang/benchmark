#include <stdio.h>

int main(void) {
    int a = 1, b = 1, sum = 0;
    for (int i = 0; i < 30; i++) {
        printf("%s%d", i ? " ": "", a);
        sum += a;
        int t = a + b;
        a = b;
        b = t;
    }
    printf("\nsum: %d\n", sum);
    return 0;
}

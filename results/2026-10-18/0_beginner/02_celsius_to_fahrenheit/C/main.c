#include <stdio.h>

int main(void) {
    int celsius[] = {-40, -15, -3, 0, 22, 37, 100};
    for (int i = 0; i < 7; ++i) {
        printf("%d C = %.1f F\n", celsius[i], celsius[i] * 9.0 / 5.0 + 32.0);
    }
    return 0;
}

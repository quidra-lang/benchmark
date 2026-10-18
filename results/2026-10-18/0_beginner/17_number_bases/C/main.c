#include <stdio.h>

int main(void) {
    unsigned values[] = {0, 10, 255, 1000, 43981, 65535};
    for (int i = 0; i < 6; i++) {
        unsigned n = values[i], v = n;
        char bits[33];
        int len = 0;
        do {
            bits[len++] = (char)('0' + v % 2);
            v /= 2;
        }
        while (v)
            ;
        printf("%u: bin=", n);
        while (len)
            putchar(bits[--len]);
        printf(" oct=%o hex=%X\n", n, n);
    }
    return 0;
}

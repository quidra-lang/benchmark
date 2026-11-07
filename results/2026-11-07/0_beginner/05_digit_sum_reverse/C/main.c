#include <stdio.h>

int main(void) {
    int values[] = {7, 98000, 4096, 50301, 2718281, 123456789};
    for (int i = 0; i < 6; ++i) {
        int remaining = values[i], digits = 0, sum = 0, reversed = 0;
        while (remaining > 0) {
            int digit = remaining % 10;
            ++digits;
            sum += digit;
            reversed = reversed * 10 + digit;
            remaining /= 10;
        }
        printf("%d: digits=%d sum=%d reversed=%d\n", values[i], digits, sum, reversed);
    }
    return 0;
}

#include <stdio.h>
#include <string.h>

int main(void) {
    const char *numbers[] = {"688126340316", "0128469655154", "92181914514156", "177332430060552", "7982377590420309",
        "9884593615513906"};
    for (int k = 0; k < 6; k++) {
        const char *s = numbers[k];
        int len = (int) strlen(s), sum = 0;
        for (int i = 0; i < len; i++) {
            int d = s[len - 1 - i] - '0';
            if (i % 2) {
                d *= 2;
                if (d > 9)
                    d -= 9;
            }
            sum += d;
        }
        if (sum % 10 == 0)
            printf("%s: valid\n", s);
        else {
            int expected = (10 - (sum - (s[len - 1] - '0')) % 10) % 10;
            printf("%s: invalid (expected check digit %d)\n", s, expected);
        }
    }
    return 0;
}

#include <stdio.h>
#include <string.h>

int main(void) {
    long long values[] = {0, 7, 999, 1000, -456789, 3141592, 9876543210LL};
    for (int i = 0; i < 7; i++) {
        char text[32];
        snprintf(text, sizeof text, "%lld", values[i]);
        size_t len = strlen(text), start = text[0] == '-' ? 1 : 0;
        if (start)
            putchar('-');
        for (size_t j = start; j < len; j++) {
            if (j > start && (len - j) % 3 == 0)
                putchar(',');
            putchar(text[j]);
        }
        putchar('\n');
    }
    return 0;
}

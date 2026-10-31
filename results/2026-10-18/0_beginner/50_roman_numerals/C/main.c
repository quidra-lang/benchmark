#include <stdio.h>
#include <string.h>

int value(char c) {
    switch (c) {
        case 'I': return 1;
        case 'V': return 5;
        case 'X': return 10;
        case 'L': return 50;
        case 'C': return 100;
        case 'D': return 500;
        case 'M': return 1000;
        default: return 0;
    }
}

int main(void) {
    int numbers[] = {9, 14, 49, 94, 444, 1994, 2768, 3999};
    int values[] = {1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1};
    const char *symbols[] = {"M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"};
    for (int k = 0; k < 8; k++) {
        int remaining = numbers[k];
        char roman[64] = "";
        for (int i = 0; i < 13; i++)
            while (remaining >= values[i]) {
                strcat(roman, symbols[i]);
                remaining -= values[i];
            }
        int result = 0;
        for (int i = 0; roman[i]; i++) {
            int v = value(roman[i]), next = value(roman[i + 1]);
            result += v < next ? -v : v;
        }
        printf("%d -> %s -> %d\n", numbers[k], roman, result);
    }
    return 0;
}

#include <stdio.h>

int main(void) {
    const int years[] = {1900, 1988, 2000, 2019, 2024, 2026, 2032, 2100};
    for (int i = 0; i < 8; ++i) {
        const int year = years[i];
        const int leap = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0);
        printf("%d: %s year\n", year, leap ? "leap" : "common");
    }
    return 0;
}

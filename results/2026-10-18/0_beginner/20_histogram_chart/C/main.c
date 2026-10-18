#include <stdio.h>

int main(void) {
    const char *days[] = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
    int counts[] = {7, 12, 4, 15, 9, 18, 11};
    for (int i = 0; i < 7; i++) {
        printf("%s | ", days[i]);
        for (int j = 0; j < counts[i]; j++)
            putchar('*');
        printf(" %d\n", counts[i]);
    }
    return 0;
}

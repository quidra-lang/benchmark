#include <stdio.h>

int main(void) {
    int sales[] = {120, 135, 98, 143, 160, 152, 171, 149, 188, 176};
    for (int i = 2; i < 10; i++) {
        double avg = (sales[i - 2] + sales[i - 1] + sales[i]) / 3.0;
        printf("day %d: %.2f\n", i + 1, avg);
    }
    return 0;
}

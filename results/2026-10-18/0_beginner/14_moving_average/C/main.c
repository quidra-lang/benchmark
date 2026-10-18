#include <stdio.h>

int main(void) {
    int sales[] = {120, 135, 98, 143, 160, 152, 171, 149, 188, 176};
    for (int i = 2; i < 10; i++) {
        double avg = (sales[i - 2] + sales[i - 1] + sales[i]) / 3.0;
        int q = (int)(avg * 100 + 0.5);
        printf("day %d: %d.%02d\n", i + 1, q / 100, q % 100);
    }
    return 0;
}

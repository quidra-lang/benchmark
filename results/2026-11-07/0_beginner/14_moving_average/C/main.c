#include <stdio.h>

int main(void) {
    int sales[] = {120, 135, 98, 143, 160, 152, 171, 149, 188, 176};
    int window = 3;
    for (int i = window - 1; i < 10; i++) {
        int sum = 0;
        for (int j = i - window + 1; j <= i; ++j) sum += sales[j];
        double avg = (double)sum / window;
        printf("day %d: %.2f\n", i + 1, avg);
    }
    return 0;
}

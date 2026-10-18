#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int compare(const void *a, const void *b) {
    int x = *(const int *) a, y = *(const int *) b;
    return (x > y) - (x < y);
}

int main(void) {
    int values[] = {72, 85, 64, 90, 85, 58, 77, 85, 69, 93, 71}, sorted[11], sum = 0;
    memcpy(sorted, values, sizeof values);
    qsort(sorted, 11, sizeof(int), compare);
    for (int i = 0; i < 11; i++)
        sum += values[i];
    double mean = sum / 11.0, s = 0;
    for (int i = 0; i < 11; i++) {
        double d = values[i] - mean;
        s += d * d;
    }
    int mode = sorted[0], best = 0;
    int count = 0;
    for (int i = 0; i < 11; i++) {
        count = i && sorted[i] == sorted[i - 1] ? count + 1 : 1;
        if (count > best) {
            best = count;
            mode = sorted[i];
        }
    }
    printf("mean: %.3f\nmedian: %d\nmode: %d\nrange: %d\nstdev: %.3f\n",
           mean, sorted[5], mode, sorted[10] - sorted[0], sqrt(s / 11.0));
    return 0;
}

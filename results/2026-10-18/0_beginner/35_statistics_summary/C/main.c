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
    for (int i = 0; i < 11; i++) {
        int count = 0;
        for (int j = 0; j < 11; j++)
            if (sorted[j] == sorted[i])
                count++;
        if (count > best) {
            best = count;
            mode = sorted[i];
        }
    }
    int m = (int)(mean * 1000 + 0.5), sd = (int)(sqrt(s / 11.0) * 1000 + 0.5);
    printf("mean: %d.%03d\nmedian: %d\nmode: %d\nrange: %d\nstdev: %d.%03d\n", m / 1000, m % 1000, sorted[5],
        mode, sorted[10] - sorted[0], sd / 1000, sd % 1000);
    return 0;
}

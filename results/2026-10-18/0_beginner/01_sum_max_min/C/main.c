#include <stdio.h>

int main(void) {
    const int values[] = {17, -8, 42, 5, -23, 36, 5, 0, -11, 29};
    int sum = 0, maximum = values[0], minimum = values[0];
    for (int i = 0; i < 10; ++i) {
        sum += values[i];
        if (values[i] > maximum) maximum = values[i];
        if (values[i] < minimum) minimum = values[i];
    }
    printf("sum: %d\nmax: %d\nmin: %d\n", sum, maximum, minimum);
    return 0;
}

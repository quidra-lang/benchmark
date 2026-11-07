#include <stdio.h>

int main(void) {
    int values[] = {48, 73, 56, 91, 35, 62, 84};
    int count = (int)(sizeof values / sizeof values[0]);
    int sum = 0;
    for (int i = 0; i < count; ++i) sum += values[i];
    double mean = (double)sum / count;
    printf("%.2f\n", mean);
    return 0;
}

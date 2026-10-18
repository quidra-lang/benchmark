#include <stdio.h>

int main(void) {
    const int values[] = {48, 73, 56, 91, 35, 62, 84};
    const int count = (int)(sizeof values / sizeof values[0]);
    int sum = 0;
    for (int i = 0; i < count; ++i) sum += values[i];
    const double mean = (double)sum / count;
    const int hundredths = (int)(mean * 100.0 + 0.5);
    printf("%d.%02d\n", hundredths / 100, hundredths % 100);
    return 0;
}

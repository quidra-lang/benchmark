#include <stdio.h>

int main(void) {
    int radii[] = {3, 7, 12, 25, 41};
    const double pi = 3.141592653589793;
    for (int i = 0; i < 5; ++i) {
        int radius = radii[i];
        printf("r=%d area=%.3f circumference=%.3f\n", radius,
               pi * radius * radius, 2.0 * pi * radius);
    }
    return 0;
}

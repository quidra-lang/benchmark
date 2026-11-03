#include <stdio.h>

int main(void) {
    int radii[] = {3, 7, 12, 25, 41};
    const double pi = 3.141592653589793;
    for (int i = 0; i < 5; ++i) {
        printf("r=%d area=%.3f circumference=%.3f\n", radii[i],
               pi * radii[i] * radii[i], 2.0 * pi * radii[i]);
    }
    return 0;
}

#include <stdio.h>

int main(void) {
    const int radii[] = {3, 7, 12, 25, 41};
    const double pi = 3.141592653589793;
    for (int i = 0; i < 5; ++i) {
        const double radius = radii[i];
        const double area = pi * radius * radius;
        const double circumference = 2.0 * pi * radius;
        const long long area_milli = (long long)(area * 1000.0 + 0.5);
        const long long circumference_milli = (long long)(circumference * 1000.0 + 0.5);
        printf("r=%d area=%lld.%03lld circumference=%lld.%03lld\n", radii[i],
               area_milli / 1000, area_milli % 1000,
               circumference_milli / 1000, circumference_milli % 1000);
    }
    return 0;
}

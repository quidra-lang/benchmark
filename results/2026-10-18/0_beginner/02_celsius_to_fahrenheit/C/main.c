#include <stdio.h>

int main(void) {
    const int celsius[] = {-40, -15, -3, 0, 22, 37, 100};
    for (int i = 0; i < 7; ++i) {
        const double fahrenheit = celsius[i] * 9.0 / 5.0 + 32.0;
        const int negative = fahrenheit < 0.0;
        const double magnitude = negative ? -fahrenheit : fahrenheit;
        const int tenths = (int)(magnitude * 10.0 + 0.5);
        printf("%d C = %s%d.%d F\n", celsius[i], negative ? "-" : "",
               tenths / 10, tenths % 10);
    }
    return 0;
}

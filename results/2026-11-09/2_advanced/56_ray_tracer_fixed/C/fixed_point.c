#include "renderer.h"
I floor_div(I a, I b) {
    I quotient = a / b, remainder = a % b;
    return quotient - (remainder != 0 && ((remainder < 0) != (b < 0)));
}
I mul(I a, I b) {
    return floor_div(a * b, SCALE);
}
I isqrt(I value) {
    if (!value)
        return 0;
    I x = value, y = (x + 1) / 2;
    while (y < x) {
        x = y;
        y = (x + value / x) / 2;
    }
    return x;
}

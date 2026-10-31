#include "ecg.h"
Integer floor_div(Integer a, Integer b) {
    Integer quotient = a / b;
    if (a % b < 0)
        --quotient;
    return quotient;
}
Integer rdiv(Integer a, Integer b) {
    return floor_div(2 * a + b, 2 * b);
}
char *decimal2(Integer value) {
    Integer magnitude = value < 0 ? -value : value;
    return format("%s%lld.%02lld", value < 0 ? "-" : "", (long long)(magnitude / 100),
                  (long long)(magnitude % 100));
}
char *decimal4(Integer value) {
    return format("%lld.%04lld", (long long)(value / 10000), (long long)(value % 10000));
}
char *reduced(Integer a, Integer b) {
    Integer x = a, y = b;
    while (y) {
        Integer remainder = x % y;
        x = y;
        y = remainder;
    }
    return format("%lld/%lld", (long long)(a / x), (long long)(b / x));
}
char *ratio(Integer a, Integer b) {
    if (!b)
        return format("%lld/%lld none", (long long)a, (long long)b);
    char *fraction = reduced(a, b), *percent = decimal2(rdiv(10000 * a, b));
    char *out = format("%lld/%lld reduced=%s percent=%s", (long long)a, (long long)b, fraction, percent);
    free(fraction);
    free(percent);
    return out;
}
char *optional_number(bool exists, Integer value) {
    return exists ? format("%lld", (long long)value) : text("-");
}

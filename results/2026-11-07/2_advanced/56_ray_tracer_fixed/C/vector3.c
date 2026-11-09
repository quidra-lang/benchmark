#include "renderer.h"
Vec add(Vec a, Vec b) {
    for (int i = 0; i < 3; ++i)
        a.data[i] += b.data[i];
    return a;
}
Vec sub(Vec a, Vec b) {
    for (int i = 0; i < 3; ++i)
        a.data[i] -= b.data[i];
    return a;
}
Vec negate(Vec value) {
    for (int i = 0; i < 3; ++i)
        value.data[i] = -value.data[i];
    return value;
}
I dot(Vec a, Vec b) {
    return floor_div(a.data[0] * b.data[0] + a.data[1] * b.data[1] + a.data[2] * b.data[2], SCALE);
}
Vec sc(Vec value, I weight) {
    for (int i = 0; i < 3; ++i)
        value.data[i] = floor_div(value.data[i] * weight, SCALE);
    return value;
}
I length(Vec value) {
    return isqrt(value.data[0] * value.data[0] + value.data[1] * value.data[1] +
                 value.data[2] * value.data[2]);
}
Vec norm(Vec value) {
    I magnitude = length(value);
    for (int i = 0; i < 3; ++i)
        value.data[i] = floor_div(value.data[i] * SCALE, magnitude);
    return value;
}

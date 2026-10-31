#include "renderer.hpp"
Vec add(Vec a, Vec b) {
    for (int i = 0; i < 3; ++i)
        a[i] += b[i];
    return a;
}
Vec sub(Vec a, Vec b) {
    for (int i = 0; i < 3; ++i)
        a[i] -= b[i];
    return a;
}
Vec negate(Vec value) {
    for (I &component : value)
        component = -component;
    return value;
}
I dot(Vec a, Vec b) {
    return floor_div(a[0] * b[0] + a[1] * b[1] + a[2] * b[2], scale);
}
Vec sc(Vec value, I weight) {
    for (I &component : value)
        component = floor_div(component * weight, scale);
    return value;
}
I length(Vec value) {
    return isqrt(value[0] * value[0] + value[1] * value[1] + value[2] * value[2]);
}
Vec norm(Vec value) {
    const I magnitude = length(value);
    for (I &component : value)
        component = floor_div(component * scale, magnitude);
    return value;
}

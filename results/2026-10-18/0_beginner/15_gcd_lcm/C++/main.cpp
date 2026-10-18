#include <iostream>
#include <array>

int gcd(int a, int b) {
    while (b) {
        int r = a % b;
        a = b;
        b = r;
    }
    return a;
}

int main() {
    const std::array<std::array<int, 2>, 5> pairs = {{{48, 180}, {1071, 462}, {7, 91}, {13, 97}, {36288,
        98280}}};
    for (const std::array<int, 2> &p : pairs) {
        int a = p[0], b = p[1], g = gcd(a, b), l = a / g * b;
        std::cout << "gcd(" << a << ", " << b << ") = " << g << ", lcm(" << a << ", " << b << ") = "
            << l << '\n';
    }
}

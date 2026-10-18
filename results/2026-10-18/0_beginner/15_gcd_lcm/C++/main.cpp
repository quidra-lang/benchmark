#include <iostream>

int gcd(int a, int b) {
    while (b) {
        int r = a % b;
        a = b;
        b = r;
    }
    return a;
}

int main() {
    int pairs[][2] = {{48, 180}, {1071, 462}, {7, 91}, {13, 97}, {36288, 98280}};
    for (auto [a, b] : pairs) {
        int g = gcd(a, b);
        std::cout << "gcd(" << a << ", " << b << ") = " << g
                  << ", lcm(" << a << ", " << b << ") = " << a / g * b << '\n';
    }
}

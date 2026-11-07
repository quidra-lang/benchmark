#include <algorithm>
#include <cmath>
#include <iomanip>
#include <iostream>

int main() {
    int coefficients[][3] = {{1, -3, -10}, {-2, 5, 4}, {3, 1, -2}, {4, -12, 9}, {1, 2, 5}, {-2, 3, -4}};
    std::cout << std::fixed << std::setprecision(4);
    for (auto [a, b, c] : coefficients) {
        int d = b * b - 4 * a * c;
        std::cout << a << ' ' << b << ' ' << c << ": ";
        if (d > 0) {
            double root = std::sqrt(d);
            double x = (-b + root) / (2.0 * a), y = (-b - root) / (2.0 * a);
            std::cout << "x1 = " << std::max(x, y) << ", x2 = " << std::min(x, y) << '\n';
        } else if (d == 0) {
            std::cout << "x = " << -b / (2.0 * a) << '\n';
        } else {
            double p = -b / (2.0 * a), q = std::sqrt(-d) / (2.0 * std::abs(a));
            std::cout << "x = " << p << " + " << q << "i, " << p << " - " << q << "i\n";
        }
    }
}

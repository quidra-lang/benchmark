#include <iostream>
#include <iomanip>
#include <string>
#include <algorithm>
#include <cmath>
#include <sstream>

std::string decimal(double x) {
    long long q = static_cast<long long>(std::abs(x) * 10000 + 0.5);
    std::ostringstream out;
    out << (x < 0 ? "-" : "") << q / 10000 << '.' << std::setfill('0') << std::setw(4) << q % 10000;
    return out.str();
}

int main() {
    const int coefficients[][3] = {{1, -3, -10}, {-2, 5, 4}, {3, 1, -2}, {4, -12, 9}, {1, 2, 5}, {-2,
        3, -4}};
    for (const int(&p)[3] : coefficients) {
        int a = p[0], b = p[1], c = p[2], d = b * b - 4 * a * c;
        std::cout << a << ' ' << b << ' ' << c << ": ";
        if (d > 0) {
            double x = (-b + std::sqrt(d)) / (2.0 * a), y = (-b - std::sqrt(d)) / (2.0 * a);
            if (x < y)
                std::swap(x, y);
            std::cout << "x1 = " << decimal(x) << ", x2 = " << decimal(y) << '\n';
        } else if (d == 0)
            std::cout << "x = " << decimal(-b / (2.0 * a)) << '\n';
        else {
            std::string p = decimal(-b / (2.0 * a)), q = decimal(std::sqrt(-d) / (2.0 * std::abs(a)));
            std::cout << "x = " << p << " + " << q << "i, " << p << " - " << q << "i\n";
        }
    }
}

#include <array>
#include <iomanip>
#include <iostream>

int main() {
    std::array<int, 5> radii = {3, 7, 12, 25, 41};
    const double pi = 3.141592653589793;
    std::cout << std::fixed << std::setprecision(3);
    for (int radius : radii) {
        std::cout << "r=" << radius << " area=" << pi * radius * radius
                  << " circumference=" << 2.0 * pi * radius << '\n';
    }
}

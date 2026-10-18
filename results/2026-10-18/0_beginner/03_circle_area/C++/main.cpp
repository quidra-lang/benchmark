#include <array>
#include <iomanip>
#include <iostream>

int main() {
    const std::array<int, 5> radii = {3, 7, 12, 25, 41};
    const double pi = 3.141592653589793;
    std::cout << std::setfill('0');
    for (int radius : radii) {
        const double area = pi * radius * radius;
        const double circumference = 2.0 * pi * radius;
        const long long area_milli = static_cast<long long>(area * 1000.0 + 0.5);
        const long long circumference_milli = static_cast<long long>(circumference * 1000.0 + 0.5);
        std::cout << "r=" << radius << " area=" << area_milli / 1000 << '.'
                  << std::setw(3) << area_milli % 1000 << " circumference="
                  << circumference_milli / 1000 << '.' << std::setw(3)
                  << circumference_milli % 1000 << '\n';
    }
}

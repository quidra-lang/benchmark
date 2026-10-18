#include <iostream>
#include <iomanip>
#include <vector>
#include <array>
#include <cmath>

int main() {
    const std::vector<std::vector<std::array<int, 2>>> polygons = {{{0, 0}, {5, 0}, {6, 4}, {1, 3}},
        {{2, 1}, {0, 4}, {3, 7}, {7, 6}, {8, 2}}, {{0, 0}, {8, 0}, {8, 6}, {5, 6}, {4, 3}, {3, 6}, {0, 6}}};
    for (std::size_t k = 0; k < polygons.size(); k++) {
        int twice = 0;
        double perimeter = 0;
        const std::vector<std::array<int, 2>> &p = polygons[k];
        for (std::size_t i = 0; i < p.size(); i++) {
            std::size_t j = (i + 1) % p.size();
            int dx = p[i][0] - p[j][0], dy = p[i][1] - p[j][1];
            twice += p[i][0] * p[j][1] - p[j][0] * p[i][1];
            perimeter += std::sqrt(dx * dx + dy * dy);
        }
        twice = std::abs(twice);
        int q = static_cast<int>(perimeter * 1000 + 0.5);
        std::cout << "polygon " << k + 1 << ": area=" << twice / 2 << '.' << twice % 2 * 5 << " perimeter="
            << q / 1000 << '.' << std::setfill('0') << std::setw(3) << q % 1000 << '\n';
    }
}

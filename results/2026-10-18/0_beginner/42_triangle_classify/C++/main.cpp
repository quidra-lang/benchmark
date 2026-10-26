#include <iostream>
#include <array>
#include <algorithm>

int main() {
    int values[][3] = {{3, 8, 5}, {6, 6, 6}, {5, 8, 5}, {13, 5, 12}, {2, 9, 4}, {7, 4, 7}, {8, 6, 7}, {4, 9, 6}};
    for (const int(&p)[3] : values) {
        std::array<int, 3> a = {p[0], p[1], p[2]};
        std::sort(a.begin(), a.end());
        std::cout << p[0] << ' ' << p[1] << ' ' << p[2] << ": ";
        if (a[0] + a[1] <= a[2]) {
            std::cout << "not a triangle\n";
        } else {
            const char *side = a[0] == a[2] ? "equilateral" : a[0] == a[1] || a[1] == a[2] ? "isosceles" : "scalene";
            int d = a[2] * a[2] - a[0] * a[0] - a[1] * a[1];
            std::cout << side << ' ' << (d < 0 ? "acute" : d == 0 ? "right" : "obtuse") << '\n';
        }
    }
}

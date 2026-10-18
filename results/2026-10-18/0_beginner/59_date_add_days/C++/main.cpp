#include <iostream>
#include <iomanip>
#include <array>

int days(int y, int m) {
    const std::array<int, 12> lengths = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    return lengths[m - 1] + (m == 2 && (y % 400 == 0 || (y % 4 == 0 && y % 100 != 0)));
}

int main() {
    const int cases[][4] = {{1999, 12, 25, 10}, {2000, 2, 27, 3}, {2021, 2, 20, 14}, {2023, 11, 15,
        120}, {2026, 10, 17, 1500}};
    for (const int(&p)[4] : cases) {
        int y = p[0], m = p[1], d = p[2], n = p[3];
        for (int i = 0; i < n; i++) {
            ++d;
            if (d > days(y, m)) {
                d = 1;
                ++m;
                if (m > 12) {
                    m = 1;
                    ++y;
                }
            }
        }
        std::cout << std::setfill('0') << std::setw(4) << p[0] << '-' << std::setw(2) << p[1] << '-'
            << std::setw(2) << p[2] << " + " << n << " days = " << std::setw(4) << y << '-' << std::setw(2)
            << m << '-' << std::setw(2) << d << '\n';
    }
}

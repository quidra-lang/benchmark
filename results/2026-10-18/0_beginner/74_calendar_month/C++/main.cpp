#include <iostream>
#include <iomanip>
#include <string>
#include <array>

int main() {
    const std::array<std::string, 12> names = {"January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"};
    const int cases[][2] = {{2024, 2}, {2026, 8}, {2026, 11}};
    const int lengths[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    for (int k = 0; k < 3; k++) {
        int y = cases[k][0], m = cases[k][1], yy = y, mm = m;
        if (mm < 3) {
            mm += 12;
            --yy;
        }
        int h = (1 + 13 * (mm + 1) / 5 + yy % 100 + (yy % 100) / 4 + (yy / 100) / 4 + 5 * (yy / 100)) % 7;
        int start = (h + 6) % 7;
        int days = lengths[m - 1] + (m == 2 && (y % 400 == 0 || (y % 4 == 0 && y % 100 != 0)));
        if (k)
            std::cout << '\n';
        std::cout << names[m - 1] << ' ' << y << "\nSu Mo Tu We Th Fr Sa\n" << std::string(start * 3, ' ');
        for (int d = 1; d <= days; d++) {
            int col = (start + d - 1) % 7;
            if (d > 1 && col)
                std::cout << ' ';
            std::cout << std::setw(2) << d;
            if (col == 6 || d == days)
                std::cout << '\n';
        }
    }
}

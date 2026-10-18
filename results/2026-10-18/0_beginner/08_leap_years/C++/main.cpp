#include <array>
#include <iostream>

int main() {
    const std::array<int, 8> years = {1900, 1988, 2000, 2019, 2024, 2026, 2032, 2100};
    for (int year : years) {
        const bool leap = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0);
        std::cout << year << ": " << (leap ? "leap" : "common") << " year\n";
    }
}

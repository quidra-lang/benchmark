#include <iostream>
#include <iomanip>
#include <array>

int main() {
    const std::array<int, 6> values = {0, 59, 3725, 45296, 86400, 312047};
    for (int s : values)
        std::cout << s << " seconds = " << std::setfill('0') << std::setw(2) << s / 3600 << ':' << std::setw(2)
            << s / 60 % 60 << ':' << std::setw(2) << s % 60 << '\n';
}

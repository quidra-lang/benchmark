#include <iostream>
#include <string>
#include <array>

int main() {
    std::array<std::string, 7> days = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
    std::array<int, 7> counts = {7, 12, 4, 15, 9, 18, 11};
    for (int i = 0; i < 7; i++)
        std::cout << days[i] << " | " << std::string(counts[i], '*') << ' ' << counts[i] << '\n';
}

#include <iostream>
#include <string>
#include <array>
#include <algorithm>

int main() {
    std::array<std::string, 6> names = {"Sato", "Suzuki", "Takahashi", "Tanaka", "Ito", "Watanabe"};
    std::array<int, 6> usage = {85, 120, 254, 300, 438, 176};
    int total = 0;
    for (int i = 0; i < 6; i++) {
        int u = usage[i], bill = 900 + std::min(u, 120) * 30 + std::clamp(u - 120, 0, 180) * 36 + std::max(0,
            u - 300) * 40;
        total += bill;
        std::cout << names[i] << ": " << u << " kWh, " << bill << " yen\n";
    }
    std::cout << "total: " << total << " yen\n";
}

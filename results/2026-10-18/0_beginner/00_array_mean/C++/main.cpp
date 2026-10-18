#include <array>
#include <iomanip>
#include <iostream>

int main() {
    const std::array<int, 7> values = {48, 73, 56, 91, 35, 62, 84};
    int sum = 0;
    for (int value : values) sum += value;
    const double mean = static_cast<double>(sum) / values.size();
    const int hundredths = static_cast<int>(mean * 100.0 + 0.5);
    std::cout << hundredths / 100 << '.' << std::setw(2)
              << std::setfill('0') << hundredths % 100 << '\n';
}

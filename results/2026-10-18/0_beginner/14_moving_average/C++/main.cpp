#include <iostream>
#include <iomanip>
#include <array>

int main() {
    std::array<int, 10> sales = {120, 135, 98, 143, 160, 152, 171, 149, 188, 176};
    std::cout << std::fixed << std::setprecision(2);
    for (int i = 2; i < 10; i++) {
        double avg = (sales[i - 2] + sales[i - 1] + sales[i]) / 3.0;
        std::cout << "day " << i + 1 << ": " << avg << '\n';
    }
}

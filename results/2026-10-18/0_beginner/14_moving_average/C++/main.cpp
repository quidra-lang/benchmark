#include <iostream>
#include <iomanip>
#include <array>

int main() {
    const std::array<int, 10> sales = {120, 135, 98, 143, 160, 152, 171, 149, 188, 176};
    for (int i = 2; i < 10; i++) {
        double avg = (sales[i - 2] + sales[i - 1] + sales[i]) / 3.0;
        int q = static_cast<int>(avg * 100 + 0.5);
        std::cout << "day " << i + 1 << ": " << q / 100 << '.' << std::setfill('0') << std::setw(2)
            << q % 100 << '\n';
    }
}

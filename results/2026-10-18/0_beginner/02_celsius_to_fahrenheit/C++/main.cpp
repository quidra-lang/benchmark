#include <array>
#include <iomanip>
#include <iostream>

int main() {
    std::array<int, 7> celsius = {-40, -15, -3, 0, 22, 37, 100};
    std::cout << std::fixed << std::setprecision(1);
    for (int temperature : celsius) {
        std::cout << temperature << " C = " << temperature * 9.0 / 5.0 + 32.0 << " F\n";
    }
}

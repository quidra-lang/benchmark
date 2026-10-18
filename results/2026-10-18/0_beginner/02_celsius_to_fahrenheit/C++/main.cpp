#include <array>
#include <iostream>

int main() {
    const std::array<int, 7> celsius = {-40, -15, -3, 0, 22, 37, 100};
    for (int temperature : celsius) {
        const double fahrenheit = temperature * 9.0 / 5.0 + 32.0;
        const bool negative = fahrenheit < 0.0;
        const double magnitude = negative ? -fahrenheit : fahrenheit;
        const int tenths = static_cast<int>(magnitude * 10.0 + 0.5);
        std::cout << temperature << " C = " << (negative ? "-" : "")
                  << tenths / 10 << '.' << tenths % 10 << " F\n";
    }
}

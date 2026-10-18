#include <array>
#include <iostream>

int main() {
    const std::array<int, 10> values = {17, -8, 42, 5, -23, 36, 5, 0, -11, 29};
    int sum = 0, maximum = values[0], minimum = values[0];
    for (int value : values) {
        sum += value;
        if (value > maximum) maximum = value;
        if (value < minimum) minimum = value;
    }
    std::cout << "sum: " << sum << "\nmax: " << maximum
              << "\nmin: " << minimum << '\n';
}

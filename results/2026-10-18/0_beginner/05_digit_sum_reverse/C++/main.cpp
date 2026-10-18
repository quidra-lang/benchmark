#include <array>
#include <iostream>

int main() {
    std::array<int, 6> values = {7, 98000, 4096, 50301, 2718281, 123456789};
    for (int value : values) {
        int remaining = value, digits = 0, sum = 0, reversed = 0;
        while (remaining > 0) {
            int digit = remaining % 10;
            ++digits;
            sum += digit;
            reversed = reversed * 10 + digit;
            remaining /= 10;
        }
        std::cout << value << ": digits=" << digits << " sum=" << sum
                  << " reversed=" << reversed << '\n';
    }
}

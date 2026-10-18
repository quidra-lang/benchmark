#include <iostream>
#include <string>
#include <array>

int value(char c) {
    switch (c) {
        case 'I':
        return 1;
        case 'V':
        return 5;
        case 'X':
        return 10;
        case 'L':
        return 50;
        case 'C':
        return 100;
        case 'D':
        return 500;
        case 'M':
        return 1000;
        default:
        return 0;
    }
}

int main() {
    const std::array<int, 13> values = {1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1};
    const std::array<std::string, 13> symbols = {"M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX",
        "V", "IV", "I"};
    for (int n : std::array<int, 8>{9, 14, 49, 94, 444, 1994, 2768, 3999}) {
        int remaining = n;
        std::string roman;
        for (int i = 0; i < 13; i++)
            while (remaining >= values[i]) {
                roman += symbols[i];
                remaining -= values[i];
            }
        int result = 0;
        for (std::size_t i = 0; i < roman.size(); i++) {
            int v = value(roman[i]), next = i + 1 < roman.size() ? value(roman[i + 1]) : 0;
            result += v < next ? - v : v;
        }
        std::cout << n << " -> " << roman << " -> " << result << '\n';
    }
}

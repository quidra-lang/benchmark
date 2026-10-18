#include <iostream>
#include <string>
#include <array>
#include <algorithm>

int main() {
    std::array<int, 52> deck {};
    for (int i = 0; i < 52; i++)
        deck[i] = i;
    long long x = 2026;
    for (int i = 51; i >= 1; i--) {
        x = x * 48271 % 2147483647;
        int j = static_cast<int>(x % (i + 1));
        std::swap(deck[i], deck[j]);
    }
    const std::string ranks = "A23456789TJQK", suits = "SHDC";
    for (int i = 0; i < 52; i++) {
        if (i % 13)
            std::cout << ' ';
        std::cout << ranks[deck[i] % 13] << suits[deck[i] / 13];
        if (i % 13 == 12)
            std::cout << '\n';
    }
}

#include <iostream>
#include <array>

int main() {
    std::array<int, 9> denominations = {10000, 5000, 1000, 500, 100, 50, 10, 5, 1};
    for (int amount : std::array<int, 5>{3780, 15420, 99999, 506, 48263}) {
        int remaining = amount, total = 0;
        std::cout << amount << " yen:";
        for (int d : denominations) {
            int count = remaining / d;
            remaining %= d;
            if (count) {
                std::cout << ' ' << d << 'x' << count;
                total += count;
            }
        }
        std::cout << " (" << total << " pieces)\n";
    }
}

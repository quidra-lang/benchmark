#include <iostream>
#include <array>
#include <algorithm>

int main() {
    std::array<int, 8> a = {27, 64, 13, 88, 41, 5, 72, 36};
    int total = 0;
    for (int p = 1; p <= 7; p++) {
        int swaps = 0;
        for (int j = 0; j <= 7 - p; j++)
            if (a[j] > a[j + 1]) {
                std::swap(a[j], a[j + 1]);
                ++swaps;
            }
        total += swaps;
        std::cout << "pass " << p << ':';
        for (int n : a)
            std::cout << ' ' << n;
        std::cout << '\n';
        if (!swaps)
            break;
    }
    std::cout << "swaps: " << total << '\n';
}

#include <iostream>
#include <array>

int main() {
    std::array<int, 13> counts {
    };
    long long x = 12345;
    for (int i = 0; i < 1000; i++) {
        x = x * 48271 % 2147483647;
        int a = static_cast<int>(x % 6) + 1;
        x = x * 48271 % 2147483647;
        int b = static_cast<int>(x % 6) + 1;
        ++counts[a + b];
    }
    int best = 2;
    for (int s = 2; s <= 12; s++) {
        std::cout << s << ": " << counts[s] << '\n';
        if (counts[s] > counts[best])
            best = s;
    }
    std::cout << "most frequent: " << best << '\n';
}

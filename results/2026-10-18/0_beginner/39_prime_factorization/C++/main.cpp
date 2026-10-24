#include <iostream>
#include <array>

int main() {
    for (int value : std::array<int, 8>{84, 9973, 15625, 1001, 123456, 48000, 999958, 999999}) {
        int n = value;
        bool first = true;
        std::cout << value << " = ";
        for (int d = 2; d * d <= n; d++) {
            int e = 0;
            while (n % d == 0) {
                n /= d;
                ++e;
            }
            if (e) {
                if (!first)
                    std::cout << " * ";
                std::cout << d;
                if (e > 1)
                    std::cout << '^' << e;
                first = false;
            }
        }
        if (n > 1) {
            if (!first)
                std::cout << " * ";
            std::cout << n;
        }
        std::cout << '\n';
    }
}

#include <iostream>
#include <array>
#include <algorithm>

int main() {
    for (long long start : std::array<long long, 5>{1, 6, 27, 97, 871}) {
        long long n = start, m = n, k = 0;
        while (n != 1) {
            n = n % 2 == 0 ? n / 2 : 3 * n + 1;
            ++k;
            m = std::max(m, n);
        }
        std::cout << start << ": steps=" << k << " max=" << m << '\n';
    }
}

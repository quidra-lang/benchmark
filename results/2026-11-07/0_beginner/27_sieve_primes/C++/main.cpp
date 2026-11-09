#include <iostream>
#include <array>
#include <algorithm>

int main() {
    constexpr int limit = 200;
    std::array<bool, limit + 1> prime{};
    std::fill(prime.begin() + 2, prime.end(), true);
    for (int p = 2; p <= limit; p++)
        if (prime[p])
            for (int j = p * 2; j <= limit; j += p)
                prime[j] = false;
    int count = static_cast<int>(std::count(prime.begin(), prime.end(), true));
    std::cout << "count: " << count << '\n';
    int printed = 0;
    for (int n = 2; n <= limit; n++)
        if (prime[n]) {
            if (printed % 10)
                std::cout << ' ';
            std::cout << n;
            ++printed;
            if (printed % 10 == 0 || printed == count)
                std::cout << '\n';
        }
}

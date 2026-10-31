#include <iostream>
#include <array>
#include <algorithm>

int main() {
    std::array<bool, 201> prime{};
    std::fill(prime.begin() + 2, prime.end(), true);
    for (int p = 2; p <= 200; p++)
        if (prime[p])
            for (int j = p * 2; j <= 200; j += p)
                prime[j] = false;
    int count = static_cast<int>(std::count(prime.begin(), prime.end(), true));
    std::cout << "count: " << count << '\n';
    int printed = 0;
    for (int n = 2; n <= 200; n++)
        if (prime[n]) {
            if (printed % 10)
                std::cout << ' ';
            std::cout << n;
            ++printed;
            if (printed % 10 == 0 || printed == count)
                std::cout << '\n';
        }
}

#include <iostream>
#include <array>

int main() {
    std::array<int, 8> a = {52, 17, 38, 9, 61, 38, 24, 45};
    int total = 0;
    for (int i = 1; i < 8; i++) {
        int v = a[i], j = i, shifts = 0;
        while (j > 0 && a[j - 1] > v) {
            a[j] = a[j - 1];
            --j;
            ++shifts;
        }
        a[j] = v;
        total += shifts;
        std::cout << "i=" << i << " shifts=" << shifts << ':';
        for (int n : a)
            std::cout << ' ' << n;
        std::cout << '\n';
    }
    std::cout << "total shifts: " << total << '\n';
}

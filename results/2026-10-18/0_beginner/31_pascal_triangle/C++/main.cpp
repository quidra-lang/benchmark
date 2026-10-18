#include <iostream>
#include <array>

int main() {
    std::array<int, 12> row {
    };
    row[0] = 1;
    for (int n = 0; n < 12; n++) {
        if (n)
            for (int k = n; k > 0; k--)
                row[k] += row[k - 1];
        for (int k = 0; k <= n; k++) {
            if (k)
                std::cout << ' ';
            std::cout << row[k];
        }
        std::cout << '\n';
    }
}

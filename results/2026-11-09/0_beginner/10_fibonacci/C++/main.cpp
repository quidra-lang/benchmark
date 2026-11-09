#include <iostream>

int main() {
    int a = 1, b = 1, sum = 0;
    for (int i = 0; i < 30; ++i) {
        if (i)
            std::cout << ' ';
        std::cout << a;
        sum += a;
        int t = a + b;
        a = b;
        b = t;
    }
    std::cout << "\nsum: " << sum << '\n';
}

#include <iostream>

int main() {
    int factorial = 1;
    for (int n = 0; n <= 12; ++n) {
        if (n > 0) factorial *= n;
        std::cout << n << "! = " << factorial << '\n';
    }
}

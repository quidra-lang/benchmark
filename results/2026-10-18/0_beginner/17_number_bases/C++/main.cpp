#include <iostream>
#include <string>
#include <array>
#include <algorithm>

int main() {
    for (unsigned n : std::array<unsigned, 6>{0, 10, 255, 1000, 43981, 65535}) {
        unsigned v = n;
        std::string bits;
        do {
            bits.push_back(static_cast<char>('0' + v % 2));
            v /= 2;
        }
        while (v)
            ;
        std::reverse(bits.begin(), bits.end());
        std::cout << std::dec << n << ": bin=" << bits << " oct=" << std::oct << n << " hex=" << std::hex
            << std::uppercase << n << '\n';
    }
}

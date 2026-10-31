#include <iostream>
#include <string>
#include <array>
#include <algorithm>
#include <bitset>

int main() {
    for (unsigned n : std::array<unsigned, 6>{0, 10, 255, 1000, 43981, 65535}) {
        std::string bits = std::bitset<16>(n).to_string();
        bits.erase(0, std::min(bits.find('1'), bits.size() - 1));
        std::cout << std::dec << n << ": bin=" << bits << " oct=" << std::oct << n << " hex=" << std::hex
            << std::uppercase << n << '\n';
    }
}

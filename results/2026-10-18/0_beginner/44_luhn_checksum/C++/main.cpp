#include <iostream>
#include <string>
#include <array>

int main() {
    for (const std::string &s : std::array<std::string, 6>{"688126340316", "0128469655154", "92181914514156",
        "177332430060552", "7982377590420309", "9884593615513906"}) {
        int sum = 0;
        for (std::size_t i = 0; i < s.size(); i++) {
            int d = s[s.size() - 1 - i] - '0';
            if (i % 2) {
                d *= 2;
                if (d > 9)
                    d -= 9;
            }
            sum += d;
        }
        if (sum % 10 == 0)
            std::cout << s << ": valid\n";
        else
            std::cout << s << ": invalid (expected check digit " << (10 - (sum - (s.back() - '0')) % 10) % 10
                << ")\n";
    }
}

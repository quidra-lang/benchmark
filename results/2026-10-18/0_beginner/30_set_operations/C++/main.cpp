#include <iostream>
#include <string>
#include <vector>
#include <array>

int main() {
    std::vector<int> a = {12, 5, 8, 21, 5, 17, 3, 12, 9}, b = {8, 14, 21, 6, 14, 3, 25, 6};
    std::array<bool, 26> sa{}, sb{};
    for (int n : a)
        sa[n] = true;
    for (int n : b)
        sb[n] = true;
    std::array<std::string, 4> labels = {"union", "intersection", "difference", "symmetric difference"};
    for (int op = 0; op < 4; op++) {
        std::cout << labels[op] << ':';
        for (int n = 0; n < 26; n++) {
            bool keep = op == 0   ? (sa[n] || sb[n])
                        : op == 1 ? (sa[n] && sb[n])
                        : op == 2 ? (sa[n] && !sb[n])
                                  : (sa[n] != sb[n]);
            if (keep)
                std::cout << ' ' << n;
        }
        std::cout << '\n';
    }
}

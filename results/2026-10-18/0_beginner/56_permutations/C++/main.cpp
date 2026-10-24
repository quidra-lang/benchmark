#include <iostream>
#include <string>
#include <array>

void search(std::string &p, std::array<bool, 4> &used, int &count) {
    if (p.size() == 4) {
        std::cout << ++count << ": " << p << '\n';
        return;
    }
    for (int i = 0; i < 4; i++)
        if (!used[i]) {
            used[i] = true;
            p += static_cast<char>('A' + i);
            search(p, used, count);
            p.pop_back();
            used[i] = false;
        }
}

int main() {
    std::string permutation;
    std::array<bool, 4> used{};
    int count = 0;
    search(permutation, used, count);
}

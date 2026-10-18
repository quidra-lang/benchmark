#include <iostream>
#include <vector>
#include <algorithm>

int main() {
    const std::vector<int> values = {12, 5, 12, 8, 3, 5, 20, 8, 8, 15, 3, 7, 20, 12, 9};
    std::vector<int> unique;
    for (int n : values)
        if (std::find(unique.begin(), unique.end(), n) == unique.end())
            unique.push_back(n);
    for (std::size_t i = 0; i < unique.size(); i++) {
        if (i)
            std::cout << ' ';
        std::cout << unique[i];
    }
    std::cout << "\nremoved: " << values.size() - unique.size() << '\n';
}

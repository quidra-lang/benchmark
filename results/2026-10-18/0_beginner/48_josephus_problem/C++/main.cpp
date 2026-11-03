#include <iostream>
#include <vector>
#include <numeric>

int main() {
    int cases[][2] = {{7, 3}, {10, 2}, {41, 3}};
    for (auto [n, k] : cases) {
        int index = 0, last = 0;
        std::vector<int> people(n);
        std::iota(people.begin(), people.end(), 1);
        std::cout << "n=" << n << " k=" << k << ':';
        while (!people.empty()) {
            index = (index + k - 1) % static_cast<int>(people.size());
            last = people[index];
            std::cout << ' ' << last;
            people.erase(people.begin() + index);
        }
        std::cout << "\nsurvivor: " << last << '\n';
    }
}

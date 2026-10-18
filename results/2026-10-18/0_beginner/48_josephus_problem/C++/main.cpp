#include <iostream>
#include <vector>
#include <array>

int main() {
    for (const std::array<int, 2> &c : std::array<std::array<int, 2>, 3>{{{7, 3}, {10, 2}, {41, 3}}}) {
        int n = c[0], k = c[1], index = 0, last = 0;
        std::vector<int> people;
        for (int i = 1; i <= n; i++)
            people.push_back(i);
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

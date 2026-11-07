#include <algorithm>
#include <array>
#include <iostream>
#include <numeric>

int main() {
    std::array<int, 10> values = {17, -8, 42, 5, -23, 36, 5, 0, -11, 29};
    auto extrema = std::minmax_element(values.begin(), values.end());
    int sum = std::accumulate(values.begin(), values.end(), 0);
    std::cout << "sum: " << sum
              << "\nmax: " << *extrema.second << "\nmin: " << *extrema.first << '\n';
}

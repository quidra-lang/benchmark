#include <array>
#include <iomanip>
#include <iostream>
#include <numeric>

int main() {
    std::array<int, 7> values = {48, 73, 56, 91, 35, 62, 84};
    int sum = std::accumulate(values.begin(), values.end(), 0);
    double mean = static_cast<double>(sum) / values.size();
    std::cout << std::fixed << std::setprecision(2)
              << mean << '\n';
}

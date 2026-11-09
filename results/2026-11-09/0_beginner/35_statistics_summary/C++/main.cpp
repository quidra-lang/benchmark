#include <iostream>
#include <iomanip>
#include <array>
#include <algorithm>
#include <cmath>
#include <numeric>

int main() {
    std::array<int, 11> values = {72, 85, 64, 90, 85, 58, 77, 85, 69, 93, 71};
    std::array<int, 11> sorted = values;
    std::sort(sorted.begin(), sorted.end());
    int sum = std::accumulate(values.begin(), values.end(), 0);
    double mean = sum / 11.0, s = 0;
    for (int n : values) {
        double d = n - mean;
        s += d * d;
    }
    int mode = sorted[0], best = 0, count = 0;
    for (int i = 0; i < 11; ++i) {
        count = i && sorted[i] == sorted[i - 1] ? count + 1 : 1;
        if (count > best) {
            best = count;
            mode = sorted[i];
        }
    }
    std::cout << std::fixed << std::setprecision(3) << "mean: " << mean
              << "\nmedian: " << sorted[5] << "\nmode: " << mode
              << "\nrange: " << sorted[10] - sorted[0]
              << "\nstdev: " << std::sqrt(s / 11.0) << '\n';
}

#include <iostream>
#include <iomanip>
#include <array>
#include <algorithm>
#include <cmath>

int main() {
    const std::array<int, 11> values = {72, 85, 64, 90, 85, 58, 77, 85, 69, 93, 71};
    std::array<int, 11> sorted = values;
    std::sort(sorted.begin(), sorted.end());
    int sum = 0;
    for (int n : values)
        sum += n;
    double mean = sum / 11.0, s = 0;
    for (int n : values) {
        double d = n - mean;
        s += d * d;
    }
    int mode = sorted[0], best = 0;
    for (int n : sorted) {
        int count = static_cast<int>(std::count(sorted.begin(), sorted.end(), n));
        if (count > best) {
            best = count;
            mode = n;
        }
    }
    int m = static_cast<int>(mean * 1000 + 0.5), sd = static_cast<int>(std::sqrt(s / 11.0) * 1000 + 0.5);
    std::cout << std::setfill('0') << "mean: " << m / 1000 << '.' << std::setw(3) << m % 1000 << "\nmedian: "
        << sorted[5] << "\nmode: " << mode << "\nrange: " << sorted[10] - sorted[0] << "\nstdev: " << sd / 1000
        << '.' << std::setw(3) << sd % 1000 << '\n';
}

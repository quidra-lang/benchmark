#include <iostream>
#include <iomanip>
#include <vector>
#include <algorithm>
#include <cmath>

int main() {
    std::vector<std::vector<std::vector<double>>> systems = {{{2, -1, 3, 7}, {4, 1, -2, 3}, {-3, 5,
        1, -4}}, {{1, 3, -2, 4, 6}, {5, -2, 1, 3, -7}, {-2, 4, 6, -1, 9}, {3, 1, -4, 2, 5}}};
    for (std::size_t s = 0; s < systems.size(); s++) {
        std::vector<std::vector<double>> &a = systems[s];
        int n = static_cast<int>(a.size());
        std::vector<double> x(n);
        for (int k = 0; k < n; k++) {
            int pivot = k;
            for (int i = k + 1; i < n; i++)
                if (std::abs(a[i][k]) > std::abs(a[pivot][k]))
                    pivot = i;
            if (pivot != k)
                std::swap(a[k], a[pivot]);
            for (int i = k + 1; i < n; i++) {
                double f = a[i][k] / a[k][k];
                for (int j = k; j <= n; j++)
                    a[i][j] = a[i][j] - f * a[k][j];
            }
        }
        for (int i = n - 1; i >= 0; i--) {
            double sum = a[i][n];
            for (int j = i + 1; j < n; j++)
                sum = sum - a[i][j] * x[j];
            x[i] = sum / a[i][i];
        }
        std::cout << "system " << s + 1 << ":\n";
        for (int i = 0; i < n; i++) {
            long long q = static_cast<long long>(std::abs(x[i]) * 10000 + 0.5);
            std::cout << 'x' << i + 1 << " = " << (x[i] < 0 ? "-" : "") << q / 10000 << '.' << std::setfill('0')
                << std::setw(4) << q % 10000 << '\n';
        }
    }
}

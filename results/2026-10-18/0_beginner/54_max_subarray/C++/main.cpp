#include <iostream>
#include <vector>

int main() {
    std::vector<std::vector<int>> arrays = {{3, -5, 8, -2, 6, -9, 4, 1, -7, 5, -3, 2}, {-4, 7,
        -1, 3, -8, 10, -2, 5, -6, -2, 9, -12, 4, -1}, {-6, -3, 5, -1, -4, 3, -9, 2, 3, -1, 4, -5, 1, 6,
        -2}};
    for (const std::vector<int> &a : arrays) {
        int current = a[0], best = current, start = 0, left = 0, right = 0;
        for (int i = 1; i < static_cast<int>(a.size()); i++) {
            if (current < 0) {
                current = a[i];
                start = i;
            } else
                current += a[i];
            if (current > best) {
                best = current;
                left = start;
                right = i;
            }
        }
        std::cout << "max sum " << best << " at [" << left << ", " << right << "]\n";
    }
}

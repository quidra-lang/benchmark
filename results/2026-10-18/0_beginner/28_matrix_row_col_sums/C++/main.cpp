#include <iostream>
#include <iomanip>
#include <array>

int main() {
    int matrix[4][5] = {{125, 340, 78, 912, 456}, {603, 27, 819, 150, 384}, {0, 765, 231, 498, 62},
                        {947, 113, 586, 39, 720}};
    std::array<int, 5> columns{};
    int total = 0;
    for (int i = 0; i < 4; i++) {
        int row = 0;
        for (int j = 0; j < 5; j++) {
            std::cout << std::setw(6) << matrix[i][j];
            row += matrix[i][j];
            columns[j] += matrix[i][j];
        }
        total += row;
        std::cout << std::setw(6) << row << '\n';
    }
    for (int n : columns)
        std::cout << std::setw(6) << n;
    std::cout << std::setw(6) << total << '\n';
}

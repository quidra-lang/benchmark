#include <iostream>
#include <array>
#include <cstdlib>

void search(int n, int row, std::array<int, 8> &positions, int &count, std::array<int, 8> &first) {
    if (row == n) {
        if (n == 8 && count == 0)
            first = positions;
        ++count;
        return;
    }
    for (int col = 0; col < n; col++) {
        bool safe = true;
        for (int r = 0; r < row; r++)
            if (positions[r] == col || std::abs(positions[r] - col) == row - r) {
                safe = false;
                break;
            }
        if (safe) {
            positions[row] = col;
            search(n, row + 1, positions, count, first);
        }
    }
}

int main() {
    std::array<int, 8> first {};
    for (int n = 4; n <= 8; n++) {
        std::array<int, 8> positions {};
        int count = 0;
        search(n, 0, positions, count, first);
        std::cout << "N=" << n << ": " << count << " solutions\n";
    }
    for (int r = 0; r < 8; r++) {
        for (int c = 0; c < 8; c++)
            std::cout << (first[r] == c ? 'Q' : '.');
        std::cout << '\n';
    }
}

#include <iostream>
#include <iomanip>

int main() {
    int matrix[5][6]{}, dr[] = {0, 1, 0, -1}, dc[] = {1, 0, -1, 0}, r = 0, c = 0, d = 0;
    for (int n = 1; n <= 30; n++) {
        matrix[r][c] = n;
        if (n == 30)
            break;
        int nr = r + dr[d], nc = c + dc[d];
        if (nr < 0 || nr >= 5 || nc < 0 || nc >= 6 || matrix[nr][nc]) {
            d = (d + 1) % 4;
            nr = r + dr[d];
            nc = c + dc[d];
        }
        r = nr;
        c = nc;
    }
    for (const int(&row)[6] : matrix) {
        for (int n : row)
            std::cout << std::setw(3) << n;
        std::cout << '\n';
    }
}

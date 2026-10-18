#include <iostream>
#include <vector>

int det(const std::vector<std::vector<int>> &a) {
    int n = static_cast<int>(a.size());
    if (n == 1)
        return a[0][0];
    int result = 0;
    for (int j = 0; j < n; j++) {
        std::vector<std::vector<int>> minor;
        for (int r = 1; r < n; r++) {
            std::vector<int> row;
            for (int c = 0; c < n; c++)
                if (c != j)
                    row.push_back(a[r][c]);
            minor.push_back(row);
        }
        int term = a[0][j] * det(minor);
        result += j % 2 ? - term : term;
    }
    return result;
}

int main() {
    const std::vector<std::vector<std::vector<int>>> matrices = {{{2, -3, 1}, {5, 4, -2}, {-1, 6, 3}},
        {{3, 0, -2, 5}, {1, 4, 7, -3}, {-6, 2, 1, 8}, {9, -5, 3, 2}}, {{4, -1, 7, 0, -3}, {2, 8, -5, 6,
        1}, {-9, 3, 2, -4, 5}, {6, 0, -7, 3, -2}, {1, -6, 4, 9, 8}}};
    for (const std::vector<std::vector<int>> &a : matrices)
        std::cout << "det(" << a.size() << 'x' << a.size() << ") = " << det(a) << '\n';
}

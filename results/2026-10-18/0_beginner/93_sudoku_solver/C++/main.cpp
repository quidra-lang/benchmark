#include <iostream>
#include <string>
#include <array>

bool solve(std::array<std::array<int, 9>, 9> &board, unsigned long long &placements) {
    int row = -1, col = -1;
    for (int r = 0; r < 9 && row < 0; r++)
        for (int c = 0; c < 9; c++)
            if (board[r][c] == 0) {
                row = r;
                col = c;
                break;
            }
    if (row < 0)
        return true;
    for (int d = 1; d <= 9; d++) {
        bool safe = true;
        for (int k = 0; k < 9; k++)
            if (board[row][k] == d || board[k][col] == d)
                safe = false;
        for (int r = row / 3 * 3; r < row / 3 * 3 + 3; r++)
            for (int c = col / 3 * 3; c < col / 3 * 3 + 3; c++)
                if (board[r][c] == d)
                    safe = false;
        if (safe) {
            board[row][col] = d;
            ++placements;
            if (solve(board, placements))
                return true;
            board[row][col] = 0;
        }
    }
    return false;
}

int main() {
    const std::array<std::string, 9> rows = {"800025000", "070080005", "260400070", "000001900", "010000040",
        "600200000", "900010000", "700000004", "020000036"};
    std::array<std::array<int, 9>, 9> board {};
    for (int r = 0; r < 9; r++)
        for (int c = 0; c < 9; c++)
            board[r][c] = rows[r][c] - '0';
    unsigned long long placements = 0;
    solve(board, placements);
    for (const std::array<int, 9> &row : board) {
        for (int c = 0; c < 9; c++) {
            if (c)
                std::cout << ' ';
            std::cout << row[c];
        }
        std::cout << '\n';
    }
    std::cout << "placements: " << placements << '\n';
}

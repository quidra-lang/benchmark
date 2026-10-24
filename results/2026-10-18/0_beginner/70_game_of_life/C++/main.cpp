#include <iostream>
#include <string>
#include <array>
#include <algorithm>

int main() {
    std::array<std::string, 8> board = {".#......", "..#.....", "###.....", "........", "........",
        "........", ".....###", "........"};
    for (int g = 0; g <= 4; g++) {
        std::cout << "generation " << g << '\n';
        for (const std::string &row : board)
            std::cout << row << '\n';
        if (g == 4)
            break;
        std::array<std::string, 8> next = board;
        for (int r = 0; r < 8; r++)
            for (int c = 0; c < 8; c++) {
                int neighbors = 0;
                for (int dr = -1; dr <= 1; dr++)
                    for (int dc = -1; dc <= 1; dc++) {
                        int rr = r + dr, cc = c + dc;
                        if ((dr || dc) && rr >= 0 && rr < 8 && cc >= 0 && cc < 8 && board[rr][cc] == '#')
                            neighbors++;
                    }
                next[r][c] = neighbors == 3 || (board[r][c] == '#' && neighbors == 2) ? '#' : '.';
            }
        board = next;
    }
    int alive = 0;
    for (const std::string &row : board)
        alive += static_cast<int>(std::count(row.begin(), row.end(), '#'));
    std::cout << "alive: " << alive << '\n';
}

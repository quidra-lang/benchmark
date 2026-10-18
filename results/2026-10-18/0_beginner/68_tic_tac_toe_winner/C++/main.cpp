#include <iostream>
#include <string>
#include <array>

int main() {
    const std::array<std::array<std::string, 3>, 6> boards = {{{"XXX", "OO.", "O.X"}, {"X.O", ".X.",
        "O.."}, {"XO.", ".OX", "XO."}, {"XOX", "XOO", "OXX"}, {"X.O", "XO.", "O.X"}, {"XOX", "OXO", "OXX"}}};
    for (int k = 0; k < 6; k++) {
        const std::array<std::string, 3> &b = boards[k];
        char winner = 0;
        bool empty = false;
        for (int i = 0; i < 3; i++) {
            for (char c : b[i])
                if (c == '.')
                    empty = true;
            if (b[i][0] != '.' && b[i][0] == b[i][1] && b[i][1] == b[i][2])
                winner = b[i][0];
            if (b[0][i] != '.' && b[0][i] == b[1][i] && b[1][i] == b[2][i])
                winner = b[0][i];
        }
        if (b[0][0] != '.' && b[0][0] == b[1][1] && b[1][1] == b[2][2])
            winner = b[0][0];
        if (b[0][2] != '.' && b[0][2] == b[1][1] && b[1][1] == b[2][0])
            winner = b[0][2];
        std::cout << "board " << k + 1 << ": ";
        if (winner)
            std::cout << winner << " wins\n";
        else
            std::cout << (empty ? "in progress" : "draw") << '\n';
    }
}

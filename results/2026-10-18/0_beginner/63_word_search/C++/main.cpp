#include <iostream>
#include <string>
#include <array>

int main() {
    std::array<std::string, 10> board = {"MMONKENBIR", "PMTIGERJPL", "TGREJEDUZI", "SPYUTEJDEC",
        "WKAPSIDLBN", "KUVNGSBPRO", "RIBSDACBAM", "YWVAUAPKAH", "KYCGTHHESR", "OCCALAOKKR"};
    std::array<std::string, 6> words = {"TIGER", "ZEBRA", "MONKEY", "PANDA", "KOALA", "RABBIT"};
    const std::array<std::string, 8> names = {"E", "SE", "S", "SW", "W", "NW", "N", "NE"};
    const int dr[] = {0, 1, 1, 1, 0, -1, -1, -1}, dc[] = {1, 1, 0, -1, -1, -1, 0, 1};
    for (const std::string &word : words) {
        bool found = false;
        for (int r = 0; r < 10 && !found; r++)
            for (int c = 0; c < 10 && !found; c++)
                for (int d = 0; d < 8; d++) {
                    bool match = true;
                    for (int k = 0; k < static_cast<int>(word.size()); k++) {
                        int rr = r + dr[d] * k, cc = c + dc[d] * k;
                        if (rr < 0 || rr >= 10 || cc < 0 || cc >= 10 || board[rr][cc] != word[k]) {
                            match = false;
                            break;
                        }
                    }
                    if (match) {
                        std::cout << word << ": (" << r << ", " << c << ") " << names[d] << '\n';
                        found = true;
                        break;
                    }
                }
        if (!found)
            std::cout << word << ": not found\n";
    }
}

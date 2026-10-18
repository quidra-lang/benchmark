#include <iostream>
#include <vector>

int main() {
    std::vector<std::vector<int>> games = {{8, 1, 10, 7, 3, 9, 0, 10, 10, 2, 6, 6, 4, 0, 9, 10,
        7, 2}, {3, 4, 5, 2, 7, 1, 0, 6, 8, 1, 4, 4, 2, 3, 6, 2, 9, 0, 1, 5}, {5, 5, 0, 10, 7, 3, 9, 1, 6,
        4, 8, 2, 3, 7, 4, 6, 1, 9, 7, 3, 5}, {10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10}, {10, 9, 1,
        10, 10, 7, 2, 0, 0, 10, 8, 1, 10, 6, 4, 10}};
    for (std::size_t g = 0; g < games.size(); g++) {
        const std::vector<int> &a = games[g];
        int index = 0, total = 0;
        std::cout << "game " << g + 1 << ':';
        for (int frame = 0; frame < 10; frame++) {
            int score;
            if (frame == 9) {
                score = a[index] + a[index + 1];
                if (a[index] == 10 || score == 10)
                    score += a[index + 2];
            } else if (a[index] == 10) {
                score = 10 + a[index + 1] + a[index + 2];
                ++index;
            } else {
                score = a[index] + a[index + 1];
                if (score == 10)
                    score += a[index + 2];
                index += 2;
            }
            total += score;
            std::cout << ' ' << total;
        }
        std::cout << '\n';
    }
}

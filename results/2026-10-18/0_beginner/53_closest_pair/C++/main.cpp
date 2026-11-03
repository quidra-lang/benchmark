#include <iostream>
#include <iomanip>
#include <array>
#include <cmath>

int main() {
    int p[][2] = {
        {12, -7}, {-33, 25}, {41, 18}, {-8, -44}, {27, 39}, {-46, -12}, {5, 14}, {36, -29},
        {-19, 47}, {-2, 3}};
    std::array<int, 2> best{}, bi{}, bj{};
    for (int i = 0; i < 10; i++)
        for (int j = i + 1; j < 10; j++) {
            int dx = p[i][0] - p[j][0], dy = p[i][1] - p[j][1], d = dx * dx + dy * dy;
            for (int k = 0; k < 2; k++)
                if ((i == 0 && j == 1) || (k == 0 ? d < best[k] : d > best[k])) {
                    best[k] = d;
                    bi[k] = i;
                    bj[k] = j;
                }
        }
    std::cout << std::fixed << std::setprecision(4);
    for (int k = 0; k < 2; k++) {
        std::cout << (k ? "farthest" : "closest") << ": P" << bi[k] << " P" << bj[k]
                  << ' ' << std::sqrt(best[k]) << '\n';
    }
}

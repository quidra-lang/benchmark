#include <iostream>
#include <string>
#include <array>
#include <algorithm>

int main() {
    const std::array<std::string, 7> names = {"tent", "stove", "lantern", "rope", "camera", "blanket",
        "water"};
    const std::array<int, 7> weights = {10, 3, 2, 3, 5, 5, 6}, values = {120, 65, 45, 20, 90, 85, 100};
    int dp[8][21] {};
    for (int i = 1; i <= 7; i++)
        for (int w = 0; w <= 20; w++) {
            dp[i][w] = dp[i - 1][w];
            if (weights[i - 1] <= w)
                dp[i][w] = std::max(dp[i][w], dp[i - 1][w - weights[i - 1]] + values[i - 1]);
        }
    std::array<bool, 7> chosen {};
    int capacity = 20, total_weight = 0;
    for (int i = 7; i >= 1; i--)
        if (dp[i][capacity] != dp[i - 1][capacity]) {
            chosen[i - 1] = true;
            capacity -= weights[i - 1];
            total_weight += weights[i - 1];
        }
    std::cout << "max value: " << dp[7][20] << "\ntotal weight: " << total_weight << "\nitems:";
    for (int i = 0; i < 7; i++)
        if (chosen[i])
            std::cout << ' ' << names[i];
    std::cout << '\n';
}

#include <iostream>
#include <array>
#include <algorithm>

int main() {
    const std::array<int, 4> coins = {1, 5, 6, 9};
    std::array<int, 41> minimum {}, ways {};
    ways[0] = 1;
    for (int amount = 1; amount <= 40; amount++) {
        minimum[amount] = 1000;
        for (int coin : coins)
            if (coin <= amount)
                minimum[amount] = std::min(minimum[amount], minimum[amount - coin] + 1);
    }
    for (int coin : coins)
        for (int amount = coin; amount <= 40; amount++)
            ways[amount] += ways[amount - coin];
    for (int target : std::array<int, 6>{8, 11, 15, 22, 33, 40}) {
        int remaining = target, greedy = 0;
        for (int i = 3; i >= 0; i--) {
            greedy += remaining / coins[i];
            remaining %= coins[i];
        }
        std::cout << target << ": min=" << minimum[target] << " greedy=" << greedy << " ways=" << ways[target]
            << '\n';
    }
}

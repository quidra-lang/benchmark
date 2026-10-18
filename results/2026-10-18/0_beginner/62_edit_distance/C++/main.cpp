#include <iostream>
#include <string>
#include <vector>
#include <utility>
#include <algorithm>

int main() {
    std::pair<std::string, std::string> pairs[] = {{"kitten", "sitting"}, {"flaw", "lawn"},
        {"listen", "silent"}, {"intention", "execution"}, {"algorithm", "altruistic"}};
    for (const auto &[a, b] : pairs) {
        int m = static_cast<int>(a.size()), n = static_cast<int>(b.size());
        std::vector<std::vector<int>> dp(m + 1, std::vector<int>(n + 1));
        for (int i = 0; i <= m; i++)
            dp[i][0] = i;
        for (int j = 0; j <= n; j++)
            dp[0][j] = j;
        for (int i = 1; i <= m; i++)
            for (int j = 1; j <= n; j++)
                dp[i][j] = std::min({dp[i - 1][j] + 1, dp[i][j - 1] + 1,
                                     dp[i - 1][j - 1] + (a[i - 1] != b[j - 1])});
        std::cout << a << " -> " << b << ": " << dp[m][n] << '\n';
    }
}

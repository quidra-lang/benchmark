package main

import "fmt"

func main() {
	for _, p := range [][2]string{{"kitten", "sitting"}, {"flaw", "lawn"}, {"listen", "silent"}, {"intention",
		"execution"}, {"algorithm", "altruistic"}} {
		a, b := p[0], p[1]
		m, n := len(a), len(b)
		dp := make([][]int, m + 1)
		for i := range dp {
			dp[i] = make([]int, n + 1)
			dp[i][0] = i
		}
		for j := 0; j <= n; j++ {
			dp[0][j] = j
		}
		for i := 1; i <= m; i++ {
			for j := 1; j <= n; j++ {
				cost := 0
				if a[i - 1] != b[j - 1] {
					cost = 1
				}
				dp[i][j] = min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost)
			}
		}
		fmt.Printf("%s -> %s: %d\n", a, b, dp[m][n])
	}
}

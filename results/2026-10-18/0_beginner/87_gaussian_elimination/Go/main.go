package main

import (
	"fmt"
	"math"
)

func main() {
	systems := [][][] float64 {
		{{2, -1, 3, 7}, {4, 1, -2, 3}, {-3, 5, 1, -4}}, {{1, 3, -2, 4, 6}, {5, -2, 1, 3, -7}, {-2, 4, 6,
			-1, 9}, {3, 1, -4, 2, 5}},
	}
	for s, a := range systems {
		n := len(a)
		x := make([] float64, n)
		for k := 0; k < n; k++ {
			pivot := k
			for i := k + 1; i < n; i++ {
				if math.Abs(a[i][k]) > math.Abs(a[pivot][k]) {
					pivot = i
				}
			}
			a[k], a[pivot] = a[pivot], a[k]
			for i := k + 1; i < n; i++ {
				f := a[i][k] / a[k][k]
				for j := k; j <= n; j++ {
					a[i][j] = a[i][j] - f * a[k][j]
				}
			}
		}
		for i := n - 1; i >= 0; i-- {
			sum := a[i][n]
			for j := i + 1; j < n; j++ {
				sum = sum - a[i][j] * x[j]
			}
			x[i] = sum / a[i][i]
		}
		fmt.Printf("system %d:\n", s + 1)
		for i, value := range x {
			q := int64(math.Abs(value) * 10000 + 0.5)
			sign := ""
			if value < 0 {
				sign = "-"
			}
			fmt.Printf("x%d = %s%d.%04d\n", i + 1, sign, q / 10000, q % 10000)
		}
	}
}

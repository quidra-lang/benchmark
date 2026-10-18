package main

import (
	"fmt"
	"math"
)

func main() {
	p := [][2]int{{12, -7}, {-33, 25}, {41, 18}, {-8, -44}, {27, 39}, {-46, -12}, {5, 14}, {36, -29},
		{-19, 47}, {-2, 3}}
	best, bi, bj := [2]int{}, [2]int{}, [2]int{}
	for i := 0; i < 10; i++ {
		for j := i + 1; j < 10; j++ {
			dx, dy := p[i][0] - p[j][0], p[i][1] - p[j][1]
			d := dx * dx + dy * dy
			for k := 0; k < 2; k++ {
				if i == 0 && j == 1 || k == 0 && d < best[k] || k == 1 && d > best[k] {
					best[k], bi[k], bj[k] = d, i, j
				}
			}
		}
	}
	for k, label := range []string{"closest", "farthest"} {
		q := int(math.Sqrt(float64(best[k])) * 10000 + 0.5)
		fmt.Printf("%s: P%d P%d %d.%04d\n", label, bi[k], bj[k], q / 10000, q % 10000)
	}
}

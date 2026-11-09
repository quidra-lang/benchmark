package main

import (
	"fmt"
	"math"
)

func main() {
	coefficients := [][3]int{{1, -3, -10}, {-2, 5, 4}, {3, 1, -2}, {4, -12, 9}, {1, 2, 5}, {-2, 3, -4}}
	for _, p := range coefficients {
		a, b, c := p[0], p[1], p[2]
		d := b*b - 4*a*c
		fmt.Printf("%d %d %d: ", a, b, c)
		if d > 0 {
			root := math.Sqrt(float64(d))
			x := (-float64(b) + root) / (2 * float64(a))
			y := (-float64(b) - root) / (2 * float64(a))
			fmt.Printf("x1 = %.4f, x2 = %.4f\n", max(x, y), min(x, y))
		} else if d == 0 {
			fmt.Printf("x = %.4f\n", -float64(b)/(2*float64(a)))
		} else {
			u, v := -float64(b)/(2*float64(a)), math.Sqrt(float64(-d))/(2*math.Abs(float64(a)))
			fmt.Printf("x = %.4f + %.4fi, %.4f - %.4fi\n", u, v, u, v)
		}
	}
}

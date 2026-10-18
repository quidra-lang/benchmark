package main

import (
	"fmt"
	"math"
)

func decimal(x float64) string {
	q := int64(math.Abs(x) * 10000 + 0.5);
	sign := "";
	if x < 0 {
		sign = "-"
	};
	return fmt.Sprintf("%s%d.%04d", sign, q / 10000, q % 10000)
}

func main() {
	for _, p := range [][3]int{{1, -3, -10}, {-2, 5, 4}, {3, 1, -2}, {4, -12, 9}, {1, 2, 5}, {-2, 3,
		-4}} {
		a, b, c := p[0], p[1], p[2];
		d := b * b - 4 * a * c;
		fmt.Printf("%d %d %d: ", a, b, c);
		if d > 0 {
			x := (-float64(b) + math.Sqrt(float64(d))) / (2 * float64(a));
			y := (-float64(b) - math.Sqrt(float64(d))) / (2 * float64(a));
			fmt.Printf("x1 = %s, x2 = %s\n", decimal(max(x, y)), decimal(min(x, y)))
		} else if d == 0 {
			fmt.Printf("x = %s\n", decimal(-float64(b) / (2 * float64(a))))
		} else {
			u, v := decimal(-float64(b) / (2 * float64(a))), decimal(math.Sqrt(float64(-d)) / (2 * math.Abs(float64(a))));
			fmt.Printf("x = %s + %si, %s - %si\n", u, v, u, v)
		}
	}
}

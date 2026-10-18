package main

import (
	"fmt"
	"math"
)

func main() {
	polygons := [][][2]int{{{0, 0}, {5, 0}, {6, 4}, {1, 3}}, {{2, 1}, {0, 4}, {3, 7}, {7, 6}, {8, 2}},
		{{0, 0}, {8, 0}, {8, 6}, {5, 6}, {4, 3}, {3, 6}, {0, 6}}}
	for k, p := range polygons {
		twice, perimeter := 0, 0.0
		for i, v := range p {
			w := p[(i + 1) % len(p)]
			dx, dy := v[0] - w[0], v[1] - w[1]
			twice += v[0] * w[1] - w[0] * v[1]
			perimeter += math.Sqrt(float64(dx * dx + dy * dy))
		}
		if twice < 0 {
			twice = -twice
		}
		q := int(perimeter * 1000 + 0.5)
		fmt.Printf("polygon %d: area=%d.%d perimeter=%d.%03d\n", k + 1, twice / 2, twice % 2 * 5, q / 1000,
			q % 1000)
	}
}

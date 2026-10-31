package main

import (
	"fmt"
	"sort"
)

func cross(o, a, b [2]int) int {
	return (a[0]-o[0])*(b[1]-o[1]) - (a[1]-o[1])*(b[0]-o[0])
}

func main() {
	points := [][2]int{{3, 2}, {-6, 1}, {8, 4}, {0, 0}, {-3, 7}, {4, -3}, {1, -5}, {-2, 1}, {5, 6},
		{-6, -2}, {2, -2}, {7, -1}, {-3, 4}, {2, 8}, {-6, 3}}
	sort.Slice(points, func(i, j int) bool {
		if points[i][0] != points[j][0] {
			return points[i][0] < points[j][0]
		}
		return points[i][1] < points[j][1]
	})
	lower, upper := [][2]int{}, [][2]int{}
	for _, p := range points {
		for len(lower) >= 2 && cross(lower[len(lower)-2], lower[len(lower)-1], p) <= 0 {
			lower = lower[:len(lower)-1]
		}
		lower = append(lower, p)
	}
	for i := len(points) - 1; i >= 0; i-- {
		p := points[i]
		for len(upper) >= 2 && cross(upper[len(upper)-2], upper[len(upper)-1], p) <= 0 {
			upper = upper[:len(upper)-1]
		}
		upper = append(upper, p)
	}
	hull := append(lower[:len(lower)-1], upper[:len(upper)-1]...)
	twice := 0
	fmt.Printf("hull: %d points\n", len(hull))
	for i, p := range hull {
		q := hull[(i+1)%len(hull)]
		fmt.Printf("(%d, %d)\n", p[0], p[1])
		twice += p[0]*q[1] - q[0]*p[1]
	}
	fmt.Printf("area: %d.%d\n", twice/2, twice%2*5)
}

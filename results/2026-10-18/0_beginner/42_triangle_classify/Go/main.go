package main

import (
	"fmt"
	"slices"
)

func main() {
	triples := [][3]int{{3, 8, 5}, {6, 6, 6}, {5, 8, 5}, {13, 5, 12}, {2, 9, 4}, {7, 4, 7}, {8, 6, 7}, {4, 9, 6}}
	for _, p := range triples {
		a := p
		slices.Sort(a[:])
		fmt.Printf("%d %d %d: ", p[0], p[1], p[2])
		if a[0]+a[1] <= a[2] {
			fmt.Println("not a triangle")
		} else {
			side := "scalene"
			if a[0] == a[2] {
				side = "equilateral"
			} else if a[0] == a[1] || a[1] == a[2] {
				side = "isosceles"
			}
			d := a[2]*a[2] - a[0]*a[0] - a[1]*a[1]
			angle := "obtuse"
			if d < 0 {
				angle = "acute"
			} else if d == 0 {
				angle = "right"
			}
			fmt.Printf("%s %s\n", side, angle)
		}
	}
}

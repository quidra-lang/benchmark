package main

import "fmt"

func main() {
	polygon := [][2]int{{1, 1}, {11, 2}, {13, 9}, {9, 7}, {7, 12}, {5, 6}, {2, 10}, {3, 5}}
	for _, p := range [][2]int{{4, 8}, {6, 4}, {10, 8}, {7, 11}, {14, 3}, {12, 8}} {
		px, py := p[0], p[1]
		inside := false
		for i, v := range polygon {
			w := polygon[(i+1)%len(polygon)]
			x1, y1, x2, y2 := v[0], v[1], w[0], w[1]
			if (y1 > py) != (y2 > py) {
				intersection := float64(x1) + float64(x2-x1)*float64(py-y1)/float64(y2-y1)
				if intersection > float64(px) {
					inside = !inside
				}
			}
		}
		result := "outside"
		if inside {
			result = "inside"
		}
		fmt.Printf("(%d, %d): %s\n", px, py, result)
	}
}

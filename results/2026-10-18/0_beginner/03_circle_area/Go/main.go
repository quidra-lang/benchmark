package main

import "fmt"

func main() {
	radii := []int{3, 7, 12, 25, 41}
	pi := float64(3.141592653589793)
	for _, radius := range radii {
		r := float64(radius)
		area := pi * r * r
		circumference := 2.0 * pi * r
		areaMilli := int64(area*1000.0 + 0.5)
		circumferenceMilli := int64(circumference*1000.0 + 0.5)
		fmt.Printf("r=%d area=%d.%03d circumference=%d.%03d\n", radius,
			areaMilli/1000, areaMilli%1000, circumferenceMilli/1000, circumferenceMilli%1000)
	}
}

package main

import (
    "fmt"
    "math"
)

func main() {
    radii := []int{3, 7, 12, 25, 41}
    for _, radius := range radii {
        r := float64(radius)
        fmt.Printf("r=%d area=%.3f circumference=%.3f\n", radius,
            math.Pi*r*r, 2.0*math.Pi*r)
    }
}

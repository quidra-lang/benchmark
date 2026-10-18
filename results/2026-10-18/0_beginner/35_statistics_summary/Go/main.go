package main

import (
	"fmt"
	"math"
	"slices"
)

func main() {
	values := []int{72, 85, 64, 90, 85, 58, 77, 85, 69, 93, 71}
	sorted := slices.Clone(values)
	slices.Sort(sorted)
	sum := 0
	for _, n := range values {
		sum += n
	}
	mean := float64(sum) / 11.0
	s := 0.0
	for _, n := range values {
		d := float64(n) - mean
		s += d * d
	}
	mode, best, count := sorted[0], 0, 0
	for i, n := range sorted {
		if i > 0 && n == sorted[i-1] {
			count++
		} else {
			count = 1
		}
		if count > best {
			best, mode = count, n
		}
	}
	fmt.Printf("mean: %.3f\nmedian: %d\nmode: %d\nrange: %d\nstdev: %.3f\n",
		mean, sorted[5], mode, sorted[10]-sorted[0], math.Sqrt(s/11.0))
}

package main

import (
	"fmt"
	"math"
	"sort"
)

func main() {
	values := []int{72, 85, 64, 90, 85, 58, 77, 85, 69, 93, 71};
	sorted := append([]int(nil), values...);
	sort.Ints(sorted);
	sum := 0;
	for _, n := range values {
		sum += n
	};
	mean := float64(sum) / 11.0;
	s := 0.0;
	for _, n := range values {
		d := float64(n) - mean;
		s += d * d
	};
	mode, best := sorted[0], 0;
	for _, n := range sorted {
		count := 0;
		for _, v := range sorted {
			if v == n {
				count++
			}
		};
		if count > best {
			best, mode = count, n
		}
	};
	m, sd := int(mean * 1000 + 0.5), int(math.Sqrt(s / 11.0) * 1000 + 0.5);
	fmt.Printf("mean: %d.%03d\nmedian: %d\nmode: %d\nrange: %d\nstdev: %d.%03d\n", m / 1000, m % 1000,
		sorted[5], mode, sorted[10] - sorted[0], sd / 1000, sd % 1000)
}

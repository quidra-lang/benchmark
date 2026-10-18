package main

import (
	"fmt"
)

func main() {
	x := int64(42)
	freeTime := [2]int{}
	arrival, totalWait, maximum := 0, 0, 0
	for k := 1; k <= 20; k++ {
		x = x * 48271 % 2147483647
		arrival += int(x % 5) + 1
		x = x * 48271 % 2147483647
		service := int(x % 7) + 2
		teller := 0
		if freeTime[1] < freeTime[0] {
			teller = 1
		}
		start := max(arrival, freeTime[teller])
		end := start + service
		wait := start - arrival
		freeTime[teller] = end
		totalWait += wait
		maximum = max(maximum, wait)
		fmt.Printf("customer %d: arrive=%d start=%d end=%d teller=%d wait=%d\n", k, arrival, start, end,
			teller + 1, wait)
	}
	average := float64(totalWait) / 20.0
	q := int(average * 100 + 0.5)
	fmt.Printf("average wait: %d.%02d\nmax wait: %d\nlast departure: %d\n", q / 100, q % 100, maximum,
		max(freeTime[0], freeTime[1]))
}

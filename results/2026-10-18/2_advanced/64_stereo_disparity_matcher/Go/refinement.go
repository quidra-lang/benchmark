package main

import "fmt"

func decimal2(a, b int64) string {
	n := (200*a + b) / (2 * b)
	return fmt.Sprintf("%d.%02d", n/100, n%100)
}
func subpixel(cost []int64, d int, p Params) (string, string) {
	a, b := int64(0), int64(1)
	index := d - p.Min
	if d > p.Min && d < p.Max && cost[index-1] > cost[index] && cost[index+1] >= cost[index] {
		a = cost[index-1] - cost[index+1]
		b = 2 * (cost[index-1] - 2*cost[index] + cost[index+1])
	}
	q := (200*(int64(d)*b+a) + b) / (2 * b)
	return fmt.Sprintf("%d.%02d", q/100, q%100), decimal2(100*p.Focal*p.Baseline, q)
}
func depthHundred(d int, p Params) int64 {
	v := int64(d)
	return (200*p.Focal*p.Baseline + v) / (2 * v)
}

package main

import "fmt"

func main() {
	a := []int{52, 17, 38, 9, 61, 38, 24, 45}
	total := 0
	for i := 1; i < 8; i++ {
		v, j, shifts := a[i], i, 0
		for j > 0 && a[j - 1] > v {
			a[j] = a[j - 1]
			j--
			shifts++
		}
		a[j] = v
		total += shifts
		fmt.Printf("i=%d shifts=%d:", i, shifts)
		for _, n := range a {
			fmt.Printf(" %d", n)
		}
		fmt.Println()
	}
	fmt.Printf("total shifts: %d\n", total)
}

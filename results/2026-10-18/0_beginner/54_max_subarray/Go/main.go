package main

import "fmt"

func main() {
	arrays := [][]int{{3, -5, 8, -2, 6, -9, 4, 1, -7, 5, -3, 2}, {-4, 7, -1, 3, -8, 10, -2, 5, -6, -2,
		9, -12, 4, -1}, {-6, -3, 5, -1, -4, 3, -9, 2, 3, -1, 4, -5, 1, 6, -2}}
	for _, a := range arrays {
		current, best, start, left, right := a[0], a[0], 0, 0, 0
		for i := 1; i < len(a); i++ {
			if current < 0 {
				current = a[i]
				start = i
			} else {
				current += a[i]
			}
			if current > best {
				best, left, right = current, start, i
			}
		}
		fmt.Printf("max sum %d at [%d, %d]\n", best, left, right)
	}
}

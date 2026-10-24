package main

import "fmt"

func main() {
	for _, start := range []int64{1, 6, 27, 97, 871} {
		n, m, k := start, start, 0
		for n != 1 {
			if n % 2 == 0 {
				n /= 2
			} else {
				n = 3 * n + 1
			}
			k++
			m = max(m, n)
		}
		fmt.Printf("%d: steps=%d max=%d\n", start, k, m)
	}
}

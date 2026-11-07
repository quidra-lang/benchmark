package main

import "fmt"

func main() {
	values := []int{17, -8, 42, 5, -23, 36, 5, 0, -11, 29}
	sum, maximum, minimum := 0, values[0], values[0]
	for _, value := range values {
		sum += value
		maximum = max(maximum, value)
		minimum = min(minimum, value)
	}
	fmt.Printf("sum: %d\nmax: %d\nmin: %d\n", sum, maximum, minimum)
}

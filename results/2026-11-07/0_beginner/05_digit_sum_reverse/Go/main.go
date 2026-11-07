package main

import "fmt"

func main() {
	values := []int{7, 98000, 4096, 50301, 2718281, 123456789}
	for _, value := range values {
		remaining, digits, sum, reversed := value, 0, 0, 0
		for remaining > 0 {
			digit := remaining % 10
			digits++
			sum += digit
			reversed = reversed*10 + digit
			remaining /= 10
		}
		fmt.Printf("%d: digits=%d sum=%d reversed=%d\n", value, digits, sum, reversed)
	}
}

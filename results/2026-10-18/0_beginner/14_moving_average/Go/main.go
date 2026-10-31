package main

import "fmt"

func main() {
	sales := []int{120, 135, 98, 143, 160, 152, 171, 149, 188, 176}
	for i := 2; i < 10; i++ {
		avg := float64(sales[i-2]+sales[i-1]+sales[i]) / 3.0
		fmt.Printf("day %d: %.2f\n", i+1, avg)
	}
}

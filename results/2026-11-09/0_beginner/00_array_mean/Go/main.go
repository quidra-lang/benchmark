package main

import "fmt"

func main() {
	values := []int{48, 73, 56, 91, 35, 62, 84}
	sum := 0
	for _, value := range values {
		sum += value
	}
	mean := float64(sum) / float64(len(values))
	fmt.Printf("%.2f\n", mean)
}

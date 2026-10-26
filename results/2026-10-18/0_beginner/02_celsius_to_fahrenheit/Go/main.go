package main

import "fmt"

func main() {
	celsius := []int{-40, -15, -3, 0, 22, 37, 100}
	for _, temperature := range celsius {
		fmt.Printf("%d C = %.1f F\n", temperature, float64(temperature)*9.0/5.0+32.0)
	}
}

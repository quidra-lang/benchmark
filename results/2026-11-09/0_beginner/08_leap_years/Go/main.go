package main

import "fmt"

func main() {
	years := []int{1900, 1988, 2000, 2019, 2024, 2026, 2032, 2100}
	for _, year := range years {
		leap := year%400 == 0 || (year%4 == 0 && year%100 != 0)
		result := "common year"
		if leap {
			result = "leap year"
		}
		fmt.Printf("%d: %s\n", year, result)
	}
}

package main

import (
	"fmt"
)

func main() {
	sales := []int{120, 135, 98, 143, 160, 152, 171, 149, 188, 176}
	for i := 2; i < 10; i++ {
		avg := float64(sales[i - 2] + sales[i - 1] + sales[i]) / 3.0;
		q := int(avg * 100 + 0.5);
		fmt.Printf("day %d: %d.%02d\n", i + 1, q / 100, q % 100)
	}
}

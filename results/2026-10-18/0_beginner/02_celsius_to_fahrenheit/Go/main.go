package main

import "fmt"

func main() {
	celsius := []int{-40, -15, -3, 0, 22, 37, 100}
	for _, temperature := range celsius {
		fahrenheit := float64(temperature)*9.0/5.0 + 32.0
		sign, magnitude := "", fahrenheit
		if fahrenheit < 0.0 {
			sign, magnitude = "-", -fahrenheit
		}
		tenths := int(magnitude*10.0 + 0.5)
		fmt.Printf("%d C = %s%d.%d F\n", temperature, sign, tenths/10, tenths%10)
	}
}

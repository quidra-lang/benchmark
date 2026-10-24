package main

import "fmt"

func gcd(a, b int64) int64 {
	for b != 0 {
		a, b = b, a % b
	}
	return a
}

func main() {
	for _, p := range [][2]int64{{48, 180}, {1071, 462}, {7, 91}, {13, 97}, {36288, 98280}} {
		a, b := p[0], p[1]
		g := gcd(a, b)
		l := a / g * b
		fmt.Printf("gcd(%d, %d) = %d, lcm(%d, %d) = %d\n", a, b, g, a, b, l)
	}
}

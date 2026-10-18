package main

import (
	"fmt"
)

func main() {
	prime := [201]bool{}
	for n := 2; n <= 200; n++ {
		prime[n] = true
	}
	for p := 2; p <= 200; p++ {
		if prime[p] {
			for j := p * 2; j <= 200; j += p {
				prime[j] = false
			}
		}
	}
	primes := []int{}
	for n := 2; n <= 200; n++ {
		if prime[n] {
			primes = append(primes, n)
		}
	}
	fmt.Printf("count: %d\n", len(primes))
	for i, n := range primes {
		if i % 10 > 0 {
			fmt.Print(" ")
		}
		fmt.Print(n)
		if i % 10 == 9 || i == len(primes) - 1 {
			fmt.Println()
		}
	}
}

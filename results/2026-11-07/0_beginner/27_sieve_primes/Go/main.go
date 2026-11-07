package main

import "fmt"

func main() {
	limit := 200
	prime := make([]bool, limit+1)
	for n := 2; n <= limit; n++ {
		prime[n] = true
	}
	for p := 2; p <= limit; p++ {
		if prime[p] {
			for j := p * 2; j <= limit; j += p {
				prime[j] = false
			}
		}
	}
	primes := []int{}
	for n := 2; n <= limit; n++ {
		if prime[n] {
			primes = append(primes, n)
		}
	}
	fmt.Printf("count: %d\n", len(primes))
	for i, n := range primes {
		if i%10 > 0 {
			fmt.Print(" ")
		}
		fmt.Print(n)
		if i%10 == 9 || i == len(primes)-1 {
			fmt.Println()
		}
	}
}

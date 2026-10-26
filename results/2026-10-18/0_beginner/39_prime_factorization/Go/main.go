package main

import (
	"fmt"
	"strings"
)

func main() {
	for _, value := range []int{84, 9973, 15625, 1001, 123456, 48000, 999958, 999999} {
		n := value
		factors := []string{}
		for d := 2; d*d <= n; d++ {
			e := 0
			for n%d == 0 {
				n /= d
				e++
			}
			if e == 1 {
				factors = append(factors, fmt.Sprint(d))
			} else if e > 1 {
				factors = append(factors, fmt.Sprintf("%d^%d", d, e))
			}
		}
		if n > 1 {
			factors = append(factors, fmt.Sprint(n))
		}
		fmt.Printf("%d = %s\n", value, strings.Join(factors, " * "))
	}
}

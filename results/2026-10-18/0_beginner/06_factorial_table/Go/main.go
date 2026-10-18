package main

import "fmt"

func main() {
	factorial := 1
	for n := 0; n <= 12; n++ {
		if n > 0 {
			factorial *= n
		}
		fmt.Printf("%d! = %d\n", n, factorial)
	}
}

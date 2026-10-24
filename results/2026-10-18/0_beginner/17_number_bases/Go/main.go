package main

import "fmt"

func main() {
	for _, n := range []int{0, 10, 255, 1000, 43981, 65535} {
		fmt.Printf("%d: bin=%b oct=%o hex=%X\n", n, n, n, n)
	}
}

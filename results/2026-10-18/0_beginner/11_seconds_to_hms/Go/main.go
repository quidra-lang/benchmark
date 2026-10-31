package main

import "fmt"

func main() {
	for _, s := range []int{0, 59, 3725, 45296, 86400, 312047} {
		fmt.Printf("%d seconds = %02d:%02d:%02d\n", s, s/3600, s/60%60, s%60)
	}
}

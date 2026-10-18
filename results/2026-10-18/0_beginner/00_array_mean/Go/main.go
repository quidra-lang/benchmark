package main

import "fmt"

func main() {
	values := []int{48, 73, 56, 91, 35, 62, 84}
	sum := 0
	for _, value := range values {
		sum += value
	}
	mean := float64(sum) / float64(len(values))
	hundredths := int(mean*100.0 + 0.5)
	fmt.Printf("%d.%02d\n", hundredths/100, hundredths%100)
}

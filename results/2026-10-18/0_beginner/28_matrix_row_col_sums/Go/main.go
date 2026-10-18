package main

import (
	"fmt"
)

func main() {
	matrix := [4][5]int{{125, 340, 78, 912, 456}, {603, 27, 819, 150, 384}, {0, 765, 231, 498, 62},
		{947, 113, 586, 39, 720}};
	columns := [5]int{};
	total := 0
	for _, row := range matrix {
		sum := 0;
		for j, n := range row {
			fmt.Printf("%6d", n);
			sum += n;
			columns[j] += n
		};
		total += sum;
		fmt.Printf("%6d\n", sum)
	};
	for _, n := range columns {
		fmt.Printf("%6d", n)
	};
	fmt.Printf("%6d\n", total)
}

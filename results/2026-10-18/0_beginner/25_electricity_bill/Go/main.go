package main

import (
	"fmt"
)

func main() {
	names := []string{"Sato", "Suzuki", "Takahashi", "Tanaka", "Ito", "Watanabe"};
	usage := []int{85, 120, 254, 300, 438, 176};
	total := 0
	for i, u := range usage {
		bill := 900 + min(u, 120) * 30 + max(0, min(u - 120, 180)) * 36 + max(0, u - 300) * 40;
		total += bill;
		fmt.Printf("%s: %d kWh, %d yen\n", names[i], u, bill)
	};
	fmt.Printf("total: %d yen\n", total)
}

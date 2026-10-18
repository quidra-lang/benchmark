package main

import (
	"fmt"
)

func main() {
	a := []int{3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77};
	for _, t := range []int{42, 3, 77, 31, 50, 1} {
		lo, hi, found := 0, 15, -1;
		fmt.Printf("%d: probes", t);
		for lo <= hi {
			mid := (lo + hi) / 2;
			fmt.Printf(" %d", mid);
			if a[mid] == t {
				found = mid;
				break
			};
			if a[mid] < t {
				lo = mid + 1
			} else {
				hi = mid - 1
			}
		};
		if found >= 0 {
			fmt.Printf(" -> index %d\n", found)
		} else {
			fmt.Println(" -> not found")
		}
	}
}

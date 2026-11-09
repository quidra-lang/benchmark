package main

import "fmt"

func det(a [][]int) int {
	if len(a) == 1 {
		return a[0][0]
	}
	result := 0
	for j := range a {
		minor := [][]int{}
		for _, r := range a[1:] {
			row := []int{}
			for c, v := range r {
				if c != j {
					row = append(row, v)
				}
			}
			minor = append(minor, row)
		}
		term := a[0][j] * det(minor)
		if j%2 == 0 {
			result += term
		} else {
			result -= term
		}
	}
	return result
}

func main() {
	matrices := [][][]int{
		{{2, -3, 1}, {5, 4, -2}, {-1, 6, 3}},
		{{3, 0, -2, 5}, {1, 4, 7, -3}, {-6, 2, 1, 8}, {9, -5, 3, 2}},
		{{4, -1, 7, 0, -3}, {2, 8, -5, 6, 1}, {-9, 3, 2, -4, 5}, {6, 0, -7, 3, -2}, {1, -6, 4, 9, 8}},
	}
	for _, a := range matrices {
		fmt.Printf("det(%dx%d) = %d\n", len(a), len(a), det(a))
	}
}

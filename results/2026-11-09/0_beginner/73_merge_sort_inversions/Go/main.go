package main

import "fmt"

func mergeSort(a []int, l, r int, count *int) {
	if l == r {
		return
	}
	m := (l + r) / 2
	mergeSort(a, l, m, count)
	mergeSort(a, m+1, r, count)
	temp := []int{}
	i, j := l, m+1
	for i <= m && j <= r {
		if a[i] < a[j] {
			temp = append(temp, a[i])
			i++
		} else {
			temp = append(temp, a[j])
			j++
			*count += m - i + 1
		}
	}
	temp = append(temp, a[i:m+1]...)
	temp = append(temp, a[j:r+1]...)
	copy(a[l:r+1], temp)
	fmt.Printf("merge [%d..%d]:", l, r)
	for _, n := range a[l : r+1] {
		fmt.Printf(" %d", n)
	}
	fmt.Println()
}

func main() {
	a := []int{47, 12, 85, 33, 6, 71, 29, 58, 90, 14}
	inversions := 0
	mergeSort(a, 0, 9, &inversions)
	fmt.Print("sorted:")
	for _, n := range a {
		fmt.Printf(" %d", n)
	}
	fmt.Printf("\ninversions: %d\n", inversions)
}

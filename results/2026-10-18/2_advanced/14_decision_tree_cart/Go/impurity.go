package main

type Fraction struct{ numerator, denominator int64 }
type Statistics struct {
	size     int64
	counts   []int64
	squares  int64
	majority int
	errors   int64
}

func sum(values []int64) int64 {
	total := int64(0)
	for _, value := range values {
		total += value
	}
	return total
}
func majority(counts []int64) int {
	selected := 0
	for i := 1; i < len(counts); i++ {
		if counts[i] > counts[selected] {
			selected = i
		}
	}
	return selected
}
func squareSum(counts []int64) int64 {
	total := int64(0)
	for _, count := range counts {
		total += count * count
	}
	return total
}
func statistics(rows []Row, classes int) Statistics {
	counts := make([]int64, classes)
	for _, row := range rows {
		counts[row.label]++
	}
	selected := majority(counts)
	return Statistics{int64(len(rows)), counts, squareSum(counts), selected, int64(len(rows)) - counts[selected]}
}
func compareFractions(a, b Fraction) int {
	first, second := a.numerator*b.denominator, b.numerator*a.denominator
	if first < second {
		return -1
	}
	if first > second {
		return 1
	}
	return 0
}
func quality(left, right Statistics) Fraction {
	return Fraction{left.squares*right.size + right.squares*left.size, left.size * right.size}
}
func improves(value Fraction, parent Statistics) bool {
	return value.numerator*parent.size > parent.squares*value.denominator
}
func impurityDecrease(parent, left, right Statistics) float64 {
	l := float64(left.squares) / float64(left.size)
	r := float64(right.squares) / float64(right.size)
	p := float64(parent.squares) / float64(parent.size)
	return (l + r) - p
}

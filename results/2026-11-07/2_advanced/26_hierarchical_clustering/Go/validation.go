package main

import "math"

func correlation(xs, ys []float64) float64 {
	mx, my := sequentialSum(xs)/float64(len(xs)), sequentialSum(ys)/float64(len(ys))
	xy, xx, yy := 0.0, 0.0, 0.0
	for i, x := range xs {
		dx, dy := x-mx, ys[i]-my
		xy += dx * dy
		xx += dx * dx
		yy += dy * dy
	}
	return xy / math.Sqrt(xx*yy)
}
func contingencyTable(first, second []int, rows, columns int) [][]int {
	table := make([][]int, rows)
	for i := range table {
		table[i] = make([]int, columns)
	}
	for i, a := range first {
		table[a][second[i]]++
	}
	return table
}

type Fraction struct{ P, Q int64 }

func (f Fraction) Value() float64              { return float64(f.P) / float64(f.Q) }
func (f Fraction) Greater(other Fraction) bool { return f.P*other.Q > other.P*f.Q }
func pairCount(value int64) int64              { return value * (value - 1) / 2 }
func adjustedRandIndex(table [][]int) Fraction {
	count, same, rowPairs, columnPairs := int64(0), int64(0), int64(0), int64(0)
	columns := make([]int64, len(table[0]))
	for _, row := range table {
		total := int64(0)
		for j, value := range row {
			total += int64(value)
			same += pairCount(int64(value))
			columns[j] += int64(value)
		}
		count += total
		rowPairs += pairCount(total)
	}
	for _, total := range columns {
		columnPairs += pairCount(total)
	}
	total := pairCount(count)
	p := 2 * (total*same - rowPairs*columnPairs)
	q := total*(rowPairs+columnPairs) - 2*rowPairs*columnPairs
	if q == 0 {
		return Fraction{1, 1}
	}
	if q < 0 {
		p, q = -p, -q
	}
	a, b := p, q
	if a < 0 {
		a = -a
	}
	for b != 0 {
		a, b = b, a%b
	}
	return Fraction{p / a, q / a}
}
func silhouetteValues(partition []int, groups int, delta [][]float64) []float64 {
	sizes := make([]int, groups+1)
	for _, number := range partition {
		sizes[number]++
	}
	values := make([]float64, len(partition))
	for i, own := range partition {
		if sizes[own] == 1 {
			continue
		}
		sums := make([]float64, groups+1)
		for j, other := range partition {
			if j != i {
				sums[other] += delta[i][j]
			}
		}
		inner := sums[own] / float64(sizes[own]-1)
		outer := math.Inf(1)
		for g := 1; g <= groups; g++ {
			if g != own {
				outer = min(outer, sums[g]/float64(sizes[g]))
			}
		}
		values[i] = (outer - inner) / max(inner, outer)
	}
	return values
}

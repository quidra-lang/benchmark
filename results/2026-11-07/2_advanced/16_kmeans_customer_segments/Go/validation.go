package main

import "math"

func distanceTable(points [][]float64) [][]float64 {
	table := make([][]float64, len(points))
	for i := range table {
		table[i] = make([]float64, len(points))
	}
	for i := range points {
		for j := i + 1; j < len(points); j++ {
			distance := math.Sqrt(squaredDistance(points[i], points[j]))
			table[i][j] = distance
			table[j][i] = distance
		}
	}
	return table
}
func silhouettes(table [][]float64, labels, sizes []int) []float64 {
	values := make([]float64, len(labels))
	for i, row := range table {
		own := labels[i]
		if sizes[own] == 1 {
			continue
		}
		totals := make([]float64, len(sizes))
		for j, distance := range row {
			if j != i {
				totals[labels[j]] += distance
			}
		}
		inner := totals[own] / float64(sizes[own]-1)
		outer := math.Inf(1)
		for j, size := range sizes {
			if j != own {
				outer = min(outer, totals[j]/float64(size))
			}
		}
		largest := max(inner, outer)
		if largest != 0 {
			values[i] = (outer - inner) / largest
		}
	}
	return values
}
func calinskiHarabasz(points, centers [][]float64, sizes []int, within float64) float64 {
	overall := meanPoint(points)
	between := 0.0
	for i, center := range centers {
		between += float64(sizes[i]) * squaredDistance(center, overall)
	}
	return (between / float64(len(centers)-1)) / (within / float64(len(points)-len(centers)))
}
func daviesBouldin(points [][]float64, labels []int, centers [][]float64, sizes []int) float64 {
	spreads := make([]float64, len(centers))
	for i, point := range points {
		spreads[labels[i]] += math.Sqrt(squaredDistance(point, centers[labels[i]]))
	}
	for j := range spreads {
		spreads[j] /= float64(sizes[j])
	}
	total := 0.0
	for a := range centers {
		worst := 0.0
		for e := range centers {
			if a != e {
				value := (spreads[a] + spreads[e]) / math.Sqrt(squaredDistance(centers[a], centers[e]))
				worst = max(worst, value)
			}
		}
		total += worst
	}
	return total / float64(len(centers))
}
func elbow(k, first, last int, within, withinFirst, withinLast float64) float64 {
	x := float64(k-first) / float64(last-first)
	y := (within - withinLast) / (withinFirst - withinLast)
	return ((1 - x) - y) / math.Sqrt(2)
}
func hartigan(within, next float64, count, k int) float64 {
	return (within/next - 1) * float64(count-k-1)
}
func pairCount(size int64) int64 { return size * (size - 1) / 2 }
func adjustedRand[X, Y comparable](first []X, second []Y) float64 {
	joint := map[struct {
		x X
		y Y
	}]int64{}
	xs, ys := map[X]int64{}, map[Y]int64{}
	for i, a := range first {
		b := second[i]
		joint[struct {
			x X
			y Y
		}{a, b}]++
		xs[a]++
		ys[b]++
	}
	z := pairCount(int64(len(first)))
	shared, sx, sy := int64(0), int64(0), int64(0)
	for _, size := range joint {
		shared += pairCount(size)
	}
	for _, size := range xs {
		sx += pairCount(size)
	}
	for _, size := range ys {
		sy += pairCount(size)
	}
	numerator := 2 * (z*shared - sx*sy)
	denominator := z*(sx+sy) - 2*sx*sy
	if denominator == 0 {
		return 1
	}
	return float64(numerator) / float64(denominator)
}

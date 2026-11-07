package main

import "slices"

func squaredDistance(first, second []float64) float64 {
	total := 0.0
	for i, a := range first {
		d := a - second[i]
		total += d * d
	}
	return total
}
func assign(points, centers [][]float64) ([]int, []float64) {
	labels, errors := make([]int, len(points)), make([]float64, len(points))
	for i, point := range points {
		best := 0
		distance := squaredDistance(point, centers[0])
		for j := 1; j < len(centers); j++ {
			candidate := squaredDistance(point, centers[j])
			if candidate < distance {
				best = j
				distance = candidate
			}
		}
		labels[i] = best
		errors[i] = distance
	}
	return labels, errors
}
func meanPoint(points [][]float64) []float64 {
	totals := make([]float64, len(points[0]))
	for _, point := range points {
		for f, value := range point {
			totals[f] += value
		}
	}
	for f := range totals {
		totals[f] /= float64(len(points))
	}
	return totals
}
func clusterSizes(labels []int, k int) []int {
	sizes := make([]int, k)
	for _, label := range labels {
		sizes[label]++
	}
	return sizes
}
func clusterCenter(points [][]float64, labels []int, j int) []float64 {
	members := [][]float64{}
	for i, label := range labels {
		if label == j {
			members = append(members, points[i])
		}
	}
	return meanPoint(members)
}
func clusterCenters(points [][]float64, labels []int, k int) [][]float64 {
	centers := make([][]float64, k)
	for j := range centers {
		centers[j] = clusterCenter(points, labels, j)
	}
	return centers
}
func refill(labels []int, errors []float64, k int) int {
	sizes := clusterSizes(labels, k)
	reseeds := 0
	for j := range sizes {
		if sizes[j] > 0 {
			continue
		}
		chosen := -1
		for i, label := range labels {
			if sizes[label] >= 2 && (chosen < 0 || errors[i] > errors[chosen]) {
				chosen = i
			}
		}
		sizes[labels[chosen]]--
		sizes[j]++
		labels[chosen] = j
		errors[chosen] = 0
		reseeds++
	}
	return reseeds
}

type LloydResult struct {
	labels     []int
	centers    [][]float64
	iterations int
	converged  bool
	reseeds    int
}

func lloyd(points, initial [][]float64, limit int) LloydResult {
	k := len(initial)
	labels, errors := assign(points, initial)
	iterations, reseeds := 0, 0
	converged := false
	for iterations < limit && !converged {
		reseeds += refill(labels, errors, k)
		centers := clusterCenters(points, labels, k)
		iterations++
		next, nextErrors := assign(points, centers)
		converged = slices.Equal(next, labels)
		labels, errors = next, nextErrors
	}
	reseeds += refill(labels, errors, k)
	return LloydResult{labels, clusterCenters(points, labels, k), iterations, converged, reseeds}
}
func sse(points [][]float64, labels []int, centers [][]float64) float64 {
	total := 0.0
	for i, point := range points {
		total += squaredDistance(point, centers[labels[i]])
	}
	return total
}

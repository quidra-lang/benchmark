package main

import (
	"math"
	"slices"
)

func distance2(a, b Point) float64 { dx, dy := a.X-b.X, a.Y-b.Y; return dx*dx + dy*dy }
func distance(a, b Point) float64  { return math.Sqrt(distance2(a, b)) }
func assignments(points []DataPoint, centers []Point) []int {
	out := make([]int, len(points))
	for i, point := range points {
		best := 0
		for k := 1; k < len(centers); k++ {
			if distance2(point.Point, centers[k]) < distance2(point.Point, centers[best]) {
				best = k
			}
		}
		out[i] = best
	}
	return out
}

type KMeans struct {
	Centers           []Point
	Assignment, Sizes []int
	Iterations        int
	Inertia           float64
}

func runKMeans(points []DataPoint, initial []Point, maximum int) KMeans {
	centers := append([]Point{}, initial...)
	assigned := assignments(points, centers)
	iterations := 0
	for t := 1; t <= maximum; t++ {
		next := append([]Point{}, centers...)
		for k := range centers {
			x, y := 0.0, 0.0
			count := 0
			for i, point := range points {
				if assigned[i] == k {
					count++
					x += point.Point.X
					y += point.Point.Y
				}
			}
			if count > 0 {
				next[k] = Point{x / float64(count), y / float64(count)}
			}
		}
		centers = next
		nextAssigned := assignments(points, centers)
		iterations = t
		same := slices.Equal(assigned, nextAssigned)
		assigned = nextAssigned
		if same {
			break
		}
	}
	sizes := make([]int, len(centers))
	inertia := 0.0
	for i, point := range points {
		sizes[assigned[i]]++
		inertia += distance2(point.Point, centers[assigned[i]])
	}
	return KMeans{centers, assigned, sizes, iterations, inertia}
}

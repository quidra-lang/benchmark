package main

import (
	"fmt"
	"math"
)

type Vec [3]int64

func subtract(a, b Vec) Vec { return Vec{a[0] - b[0], a[1] - b[1], a[2] - b[2]} }
func cross(a, b Vec) Vec {
	return Vec{a[1]*b[2] - a[2]*b[1], a[2]*b[0] - a[0]*b[2], a[0]*b[1] - a[1]*b[0]}
}
func dot(a, b Vec) int64 { return a[0]*b[0] + a[1]*b[1] + a[2]*b[2] }
func normal(f *Face, points []Vec) Vec {
	a, b, c := points[f.Vertices[0]], points[f.Vertices[1]], points[f.Vertices[2]]
	return cross(subtract(b, a), subtract(c, a))
}
func determinant(f *Face, points []Vec) int64 {
	return dot(points[f.Vertices[0]], cross(points[f.Vertices[1]], points[f.Vertices[2]]))
}
func area(faces []*Face, points []Vec) float64 {
	total := 0.0
	for _, f := range faces {
		n := normal(f, points)
		total += math.Sqrt(float64(dot(n, n)))
	}
	return total / 2
}
func triangleAngle(f *Face, points []Vec) string {
	a, b, c := points[f.Vertices[0]], points[f.Vertices[1]], points[f.Vertices[2]]
	smallest := min(dot(subtract(b, a), subtract(c, a)), dot(subtract(c, b), subtract(a, b)), dot(subtract(a, c), subtract(b, c)))
	if smallest < 0 {
		return "obtuse"
	}
	if smallest == 0 {
		return "right"
	}
	return "acute"
}
func edgeLengthSquared(e Edge, points []Vec) int64 {
	d := subtract(points[e[0]], points[e[1]])
	return dot(d, d)
}
func windingNumber(ids []int, faces []*Face, points []Vec, sample Vec) int {
	total := 0.0
	for _, id := range ids {
		f := faces[id-1]
		a, b, c := subtract(points[f.Vertices[0]], sample), subtract(points[f.Vertices[1]], sample), subtract(points[f.Vertices[2]], sample)
		la, lb, lc := math.Sqrt(float64(dot(a, a))), math.Sqrt(float64(dot(b, b))), math.Sqrt(float64(dot(c, c)))
		numerator := float64(dot(a, cross(b, c)))
		denominator := la*lb*lc + float64(dot(a, b))*lc + float64(dot(b, c))*la + float64(dot(c, a))*lb
		total += 2 * math.Atan2(numerator, denominator)
	}
	return int(math.Round(total / (4 * math.Pi)))
}
func volume6(ids []int, faces []*Face, points []Vec) int64 {
	var total int64
	for _, id := range ids {
		total += determinant(faces[id-1], points)
	}
	return total
}
func centroid(ids []int, faces []*Face, points []Vec, sixVolume int64) [3]string {
	var result [3]string
	for axis := range 3 {
		var numerator int64
		for _, id := range ids {
			f := faces[id-1]
			signed := determinant(f, points)
			numerator += signed * (points[f.Vertices[0]][axis] + points[f.Vertices[1]][axis] + points[f.Vertices[2]][axis])
		}
		result[axis] = fraction(numerator, 4*sixVolume)
	}
	return result
}
func abs64(v int64) int64 {
	if v < 0 {
		return -v
	}
	return v
}
func fraction(n, d int64) string {
	if d < 0 {
		n, d = -n, -d
	}
	a, b := abs64(n), d
	for b != 0 {
		a, b = b, a%b
	}
	n /= a
	d /= a
	if d == 1 {
		return fmt.Sprint(n)
	}
	return fmt.Sprintf("%d/%d", n, d)
}
func real(value float64) string { return fmt.Sprintf("%.3f", value) }
func bbox(vertices []int, points []Vec) [6]int64 {
	p := points[vertices[0]]
	box := [6]int64{p[0], p[1], p[2], p[0], p[1], p[2]}
	for _, v := range vertices {
		for axis := range 3 {
			box[axis] = min(box[axis], points[v][axis])
			box[axis+3] = max(box[axis+3], points[v][axis])
		}
	}
	return box
}

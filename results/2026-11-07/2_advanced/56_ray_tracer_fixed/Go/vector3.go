package main

import "fmt"

type Vec [3]int64

func (v Vec) String() string   { return fmt.Sprintf("%d %d %d", v[0], v[1], v[2]) }
func add(a, b Vec) Vec         { return Vec{a[0] + b[0], a[1] + b[1], a[2] + b[2]} }
func sub(a, b Vec) Vec         { return Vec{a[0] - b[0], a[1] - b[1], a[2] - b[2]} }
func neg(a Vec) Vec            { return Vec{-a[0], -a[1], -a[2]} }
func dot(a, b Vec) int64       { return floorDiv(a[0]*b[0]+a[1]*b[1]+a[2]*b[2], S) }
func scale(a Vec, k int64) Vec { return Vec{mul(a[0], k), mul(a[1], k), mul(a[2], k)} }
func length(a Vec) int64       { return isqrt(a[0]*a[0] + a[1]*a[1] + a[2]*a[2]) }
func norm(a Vec) Vec {
	l := length(a)
	return Vec{floorDiv(a[0]*S, l), floorDiv(a[1]*S, l), floorDiv(a[2]*S, l)}
}

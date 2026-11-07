package main

import (
	"fmt"
	"math"
)

type Kernel struct {
	Name, Kind  string
	Degree      int
	Gamma, Coef float64
}

func (k Kernel) value(a, b Point) float64 {
	if k.Kind == "rbf" {
		e1, e2 := a[0]-b[0], a[1]-b[1]
		return math.Exp(-k.Gamma * (e1*e1 + e2*e2))
	}
	v := a[0]*b[0] + a[1]*b[1]
	if k.Kind == "linear" {
		return v
	}
	s := k.Gamma*v + k.Coef
	v = 1
	for d := 0; d < k.Degree; d++ {
		v *= s
	}
	return v
}
func (k Kernel) description() string {
	switch k.Kind {
	case "linear":
		return "linear"
	case "poly":
		return fmt.Sprintf("poly degree %d gamma %s coef0 %s", k.Degree, fixed(k.Gamma, 4), fixed(k.Coef, 4))
	default:
		return "rbf gamma " + fixed(k.Gamma, 4)
	}
}
func kernelMatrix(a []Example, k Kernel) [][]float64 {
	q := make([][]float64, len(a))
	for i, x := range a {
		q[i] = make([]float64, len(a))
		for j, y := range a {
			q[i][j] = k.value(x.Point, y.Point)
		}
	}
	return q
}
func subset(a []Example, q [][]float64, indices []int) ([]Example, [][]float64) {
	data := make([]Example, len(indices))
	matrix := make([][]float64, len(indices))
	for i, p := range indices {
		data[i] = a[p]
		matrix[i] = make([]float64, len(indices))
		for j, r := range indices {
			matrix[i][j] = q[p][r]
		}
	}
	return data, matrix
}

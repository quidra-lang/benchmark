package main

import "math"

func direct(plate *Plate, right [][]float64) [][]float64 {
	n, w := len(plate.C), plate.Mesh.W
	matrix := make([][]float64, n)
	for p := 0; p < n; p++ {
		matrix[p] = make([]float64, n)
		matrix[p][p] = plate.A[p]
		for _, f := range plate.Faces[p] {
			if f.Neighbor >= 0 {
				matrix[p][f.Neighbor] = -f.G
			}
		}
	}
	rhs := make([][]float64, len(right))
	for i, r := range right {
		rhs[i] = append([]float64(nil), r...)
	}
	for k := 0; k < n; k++ {
		for i := k + 1; i <= min(n-1, k+w); i++ {
			factor := matrix[i][k] / matrix[k][k]
			matrix[i][k] = 0
			for j := k + 1; j <= min(n-1, k+w); j++ {
				matrix[i][j] -= factor * matrix[k][j]
			}
			for _, r := range rhs {
				r[i] -= factor * r[k]
			}
		}
	}
	out := make([][]float64, len(rhs))
	for r, y := range rhs {
		x := make([]float64, n)
		for i := n - 1; i >= 0; i-- {
			v := y[i]
			for j := i + 1; j <= min(n-1, i+w); j++ {
				v -= matrix[i][j] * x[j]
			}
			x[i] = v / matrix[i][i]
		}
		out[r] = x
	}
	return out
}
func iterationValue(plate *Plate, x []float64, p int) float64 {
	s := 0.0
	for _, f := range plate.Faces[p] {
		if f.Neighbor >= 0 {
			s += f.G * x[f.Neighbor]
		} else if f.Boundary {
			s += f.G * f.Theta
		}
	}
	return (s + plate.Sall[p]) / plate.A[p]
}

type Solver struct {
	Name                  string
	Omega                 float64
	Field, Deltas         []float64
	Converged             bool
	Rate, Error, Residual float64
	Milestones            [4]int
}

func iterate(plate *Plate, name string, omega, initial, tolerance float64, maximum int) Solver {
	n := len(plate.C)
	out := Solver{Name: name, Omega: omega, Field: filled(n, initial)}
	for k := 1; k <= maximum; k++ {
		before := append([]float64(nil), out.Field...)
		if name == "jacobi" {
			for p := range out.Field {
				out.Field[p] = iterationValue(plate, before, p)
			}
		} else {
			for p := range out.Field {
				y := iterationValue(plate, out.Field, p)
				if name == "gauss_seidel" {
					out.Field[p] = y
				} else {
					out.Field[p] = out.Field[p] + omega*(y-out.Field[p])
				}
			}
		}
		delta := maxDifference(out.Field, before)
		out.Deltas = append(out.Deltas, delta)
		for i, factor := range []float64{1000, 100, 10, 1} {
			if out.Milestones[i] == 0 && delta < tolerance*factor {
				out.Milestones[i] = k
			}
		}
		if delta < tolerance {
			out.Converged = true
			break
		}
	}
	k := len(out.Deltas)
	out.Rate = math.Sqrt(out.Deltas[k-1] / out.Deltas[k-3])
	return out
}
func residual(plate *Plate, x, b []float64) float64 {
	maximum := 0.0
	for p := range x {
		v := b[p]
		for _, f := range plate.Faces[p] {
			if f.Neighbor >= 0 {
				v += f.G * x[f.Neighbor]
			}
		}
		v -= plate.A[p] * x[p]
		maximum = math.Max(maximum, math.Abs(v))
	}
	return maximum
}

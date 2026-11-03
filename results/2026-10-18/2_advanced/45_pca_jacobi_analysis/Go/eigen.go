package main

import (
	"math"
	"sort"
)

type EigenSystem struct {
	Values  []float64
	Vectors [][]float64
	Sweeps  int
}

func offDiagonal(a [][]float64) float64 {
	s := 0.0
	for p := 0; p < len(a)-1; p++ {
		for q := p + 1; q < len(a); q++ {
			s += a[p][q] * a[p][q]
		}
	}
	return s
}
func rotate(a, v [][]float64, p, q int) {
	if a[p][q] == 0 {
		return
	}
	theta := (a[q][q] - a[p][p]) / (2 * a[p][q])
	t := 1 / (math.Abs(theta) + math.Sqrt(theta*theta+1))
	if theta < 0 {
		t = -t
	}
	c := 1 / math.Sqrt(t*t+1)
	s := t * c
	for r := range a {
		if r == p || r == q {
			continue
		}
		x, y := a[r][p], a[r][q]
		a[r][p] = c*x - s*y
		a[p][r] = a[r][p]
		a[r][q] = s*x + c*y
		a[q][r] = a[r][q]
	}
	w := a[p][q]
	a[p][p] = a[p][p] - t*w
	a[q][q] = a[q][q] + t*w
	a[p][q] = 0
	a[q][p] = 0
	for r := range v {
		x, y := v[r][p], v[r][q]
		v[r][p] = c*x - s*y
		v[r][q] = s*x + c*y
	}
}
func jacobi(matrix [][]float64) EigenSystem {
	a := copyMatrix(matrix)
	v := identity(len(a))
	initial := offDiagonal(a)
	count := 0
	if initial > 0 {
		for number := 1; number <= 100; number++ {
			for p := 0; p < len(a)-1; p++ {
				for q := p + 1; q < len(a); q++ {
					rotate(a, v, p, q)
				}
			}
			remaining := offDiagonal(a)
			if count == 0 && remaining < 1e-16*initial {
				count = number
			}
			if remaining < 1e-22*initial {
				break
			}
		}
	}
	order := make([]int, len(a))
	for k := range order {
		order[k] = k
	}
	sort.SliceStable(order, func(i, j int) bool { return a[order[i]][order[i]] > a[order[j]][order[j]] })
	out := EigenSystem{Sweeps: count}
	for _, k := range order {
		out.Values = append(out.Values, a[k][k])
		out.Vectors = append(out.Vectors, orient(normalize(column(v, k))))
	}
	return out
}

type PowerComponent struct {
	Value     float64
	Vector    []float64
	Agreement int
}

func powerIteration(matrix, references [][]float64) []PowerComponent {
	b := copyMatrix(matrix)
	out := []PowerComponent{}
	for _, reference := range references {
		opposite := make([]float64, len(reference))
		x := make([]float64, len(reference))
		for i, v := range reference {
			opposite[i] = -v
			x[i] = 1
		}
		agreement := 0
		for step := 1; step <= 1000; step++ {
			x = normalize(multiply(b, x))
			d := math.Min(maxDifference(x, reference), maxDifference(x, opposite))
			if agreement == 0 && d < 0.000001 {
				agreement = step
			}
		}
		value := dot(x, multiply(b, x))
		vector := orient(normalize(x))
		deflate(b, value, vector)
		out = append(out, PowerComponent{value, vector, agreement})
	}
	return out
}

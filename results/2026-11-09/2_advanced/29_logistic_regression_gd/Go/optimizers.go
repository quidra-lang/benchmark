package main

import "math"

type Minstd struct{ State int64 }

func (r *Minstd) Draw() int64 { r.State = 48271 * r.State % 2147483647; return r.State }
func (r *Minstd) Shuffle(values []int) {
	for size := len(values); size > 1; size-- {
		j := int(r.Draw() % int64(size))
		values[size-1], values[j] = values[j], values[size-1]
	}
}

type Checkpoint struct {
	Iteration int
	Weights   []float64
}

func move(w, g []float64, rate float64) []float64 {
	result := make([]float64, len(w))
	for j := range w {
		result[j] = w[j] - rate*g[j]
	}
	return result
}
func gradientDescent(x [][]float64, y []int, lambda, rate float64, iterations int) []Checkpoint {
	w := make([]float64, len(x[0]))
	checkpoints := []Checkpoint{{0, w}}
	for t := 1; t <= iterations; t++ {
		w = move(w, gradient(w, x, y, lambda), rate)
		if t%100 == 0 {
			checkpoints = append(checkpoints, Checkpoint{t, w})
		}
	}
	return checkpoints
}
func stochasticDescent(x [][]float64, y []int, lambda, rate float64, batchSize, epochs int, seed int64) []Checkpoint {
	rng := Minstd{seed}
	order := make([]int, len(x))
	for i := range order {
		order[i] = i
	}
	w := make([]float64, len(x[0]))
	checkpoints := []Checkpoint{{0, w}}
	for e := 1; e <= epochs; e++ {
		rng.Shuffle(order)
		for start := 0; start < len(order); start += batchSize {
			bx := [][]float64{}
			by := []int{}
			for _, i := range order[start:min(start+batchSize, len(order))] {
				bx = append(bx, x[i])
				by = append(by, y[i])
			}
			w = move(w, gradient(w, bx, by, lambda), rate)
		}
		checkpoints = append(checkpoints, Checkpoint{e, w})
	}
	return checkpoints
}
func cholesky(a [][]float64) [][]float64 {
	n := len(a)
	lower := matrix(n, n)
	for j := 0; j < n; j++ {
		for i := j; i < n; i++ {
			total := 0.0
			for k := 0; k < j; k++ {
				total += lower[i][k] * lower[j][k]
			}
			remainder := a[i][j] - total
			if i == j {
				lower[j][j] = math.Sqrt(remainder)
			} else {
				lower[i][j] = remainder / lower[j][j]
			}
		}
	}
	return lower
}
func solve(lower [][]float64, b []float64) []float64 {
	n := len(b)
	z, x := make([]float64, n), make([]float64, n)
	for i := 0; i < n; i++ {
		total := 0.0
		for k := 0; k < i; k++ {
			total += lower[i][k] * z[k]
		}
		z[i] = (b[i] - total) / lower[i][i]
	}
	for i := n - 1; i >= 0; i-- {
		total := 0.0
		for k := i + 1; k < n; k++ {
			total += lower[k][i] * x[k]
		}
		x[i] = (z[i] - total) / lower[i][i]
	}
	return x
}
func newtonDirection(w []float64, x [][]float64, y []int, lambda float64) ([]float64, []float64) {
	g := gradient(w, x, y, lambda)
	return g, solve(cholesky(hessian(w, x, lambda)), g)
}
func newtonMethod(x [][]float64, y []int, lambda float64) []Checkpoint {
	w := make([]float64, len(x[0]))
	checkpoints := []Checkpoint{{0, w}}
	for t := 1; t <= 10; t++ {
		_, step := newtonDirection(w, x, y, lambda)
		w = move(w, step, 1)
		checkpoints = append(checkpoints, Checkpoint{t, w})
	}
	return checkpoints
}
func finalWeights(checkpoints []Checkpoint) []float64 { return checkpoints[len(checkpoints)-1].Weights }

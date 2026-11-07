package main

import "math"

type State struct {
	X []float64
	P Matrix
}
type Innovation struct {
	Nu         []float64
	S, Inverse Matrix
	Distance   float64
}

func transition(kind string, t float64) Matrix {
	n := 4
	if kind == "CA" {
		n = 6
	}
	f := identity(n)
	f[0][2], f[1][3] = t, t
	if n == 6 {
		f[0][4], f[1][5] = t*t/2, t*t/2
		f[2][4], f[3][5] = t, t
	}
	return f
}
func processNoise(kind string, t, q float64) Matrix {
	n := 4
	if kind == "CA" {
		n = 6
	}
	out := zeros(n, n)
	for axis := 0; axis < 2; axis++ {
		put := func(i, j int, v float64) { out[axis+2*i][axis+2*j] = v; out[axis+2*j][axis+2*i] = v }
		if n == 4 {
			put(0, 0, q*t*t*t/3)
			put(0, 1, q*t*t/2)
			put(1, 1, q*t)
		} else {
			put(0, 0, q*t*t*t*t*t/20)
			put(0, 1, q*t*t*t*t/8)
			put(0, 2, q*t*t*t/6)
			put(1, 1, q*t*t*t/3)
			put(1, 2, q*t*t/2)
			put(2, 2, q*t)
		}
	}
	return out
}
func measurementMatrix(n int) Matrix { h := zeros(2, n); h[0][0], h[1][1] = 1, 1; return h }
func initialize(kind string, z Point, p Params) State {
	x := []float64{z[0], z[1], 0, 0}
	d := []float64{p.Sigma * p.Sigma, p.Sigma * p.Sigma, p.Velocity, p.Velocity}
	if kind == "CA" {
		x = append(x, 0, 0)
		d = append(d, p.Acceleration, p.Acceleration)
	}
	return State{x, diagonal(d)}
}
func predict(state State, kind string, t, q float64) (State, Matrix) {
	f := transition(kind, t)
	x := matrixVector(f, state.X)
	cov := matrixAdd(product(product(f, state.P), transpose(f)), processNoise(kind, t, q), 1)
	return State{x, cov}, f
}
func innovation(state State, z Point, sigma float64) Innovation {
	nu := []float64{z[0] - state.X[0], z[1] - state.X[1]}
	s := matrixAdd(positionCovariance(state.P), diagonal([]float64{sigma * sigma, sigma * sigma}), 1)
	si := inverse(s)
	return Innovation{nu, s, si, quadratic(nu, si)}
}
func update(state State, z Point, sigma float64) (State, Innovation, float64) {
	v := innovation(state, z, sigma)
	n := len(state.X)
	h := measurementMatrix(n)
	r := diagonal([]float64{sigma * sigma, sigma * sigma})
	k := product(product(state.P, transpose(h)), v.Inverse)
	j := matrixAdd(identity(n), product(k, h), -1)
	x := vectorAdd(state.X, matrixVector(k, v.Nu), 1)
	p := matrixAdd(product(product(j, state.P), transpose(j)), product(product(k, r), transpose(k)), 1)
	likelihood := -math.Log(2*math.Pi) - math.Log(determinant(v.S))/2 - v.Distance/2
	return State{x, p}, v, likelihood
}
func smooth(states, predicted []State, transitions []Matrix) [][]float64 {
	n := len(states)
	out := make([][]float64, n)
	out[n-1] = append([]float64(nil), states[n-1].X...)
	for i := n - 2; i >= 0; i-- {
		c := product(product(states[i].P, transpose(transitions[i+1])), inverse(predicted[i+1].P))
		out[i] = vectorAdd(states[i].X, matrixVector(c, vectorAdd(out[i+1], predicted[i+1].X, -1)), 1)
	}
	return out
}

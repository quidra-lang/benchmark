package main

import "math"

type IMM struct {
	States [2]State
	Mu     [2]float64
}

func newIMM(z Point, p Params) IMM {
	return IMM{[2]State{initialize("CV", z, p), initialize("CV", z, p)}, p.IMMInitial}
}
func (m IMM) estimate() []float64 {
	out := make([]float64, 4)
	for r := range out {
		out[r] = m.Mu[0]*m.States[0].X[r] + m.Mu[1]*m.States[1].X[r]
	}
	return out
}
func (m *IMM) step(t float64, z *Point, p Params) {
	c := [2]float64{}
	for j := 0; j < 2; j++ {
		c[j] = p.IMMTransition[0][j]*m.Mu[0] + p.IMMTransition[1][j]*m.Mu[1]
	}
	mixed := [2]State{}
	for j := 0; j < 2; j++ {
		weights := [2]float64{p.IMMTransition[0][j] * m.Mu[0] / c[j], p.IMMTransition[1][j] * m.Mu[1] / c[j]}
		x := make([]float64, 4)
		cov := zeros(4, 4)
		for r := range x {
			x[r] = weights[0]*m.States[0].X[r] + weights[1]*m.States[1].X[r]
		}
		for r := 0; r < 4; r++ {
			for s := 0; s < 4; s++ {
				cov[r][s] = weights[0]*(m.States[0].P[r][s]+(m.States[0].X[r]-x[r])*(m.States[0].X[s]-x[s])) +
					weights[1]*(m.States[1].P[r][s]+(m.States[1].X[r]-x[r])*(m.States[1].X[s]-x[s]))
			}
		}
		mixed[j] = State{x, cov}
	}
	likelihood := [2]float64{1, 1}
	for j := 0; j < 2; j++ {
		state, _ := predict(mixed[j], "CV", t, p.IMMQ[j])
		if z != nil {
			var v Innovation
			state, v, _ = update(state, *z, p.Sigma)
			likelihood[j] = math.Exp(-v.Distance/2) / (2 * math.Pi * math.Sqrt(determinant(v.S)))
		}
		m.States[j] = state
	}
	den := likelihood[0]*c[0] + likelihood[1]*c[1]
	for j := 0; j < 2; j++ {
		m.Mu[j] = likelihood[j] * c[j] / den
	}
}

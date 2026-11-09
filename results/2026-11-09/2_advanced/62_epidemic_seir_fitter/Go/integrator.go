package main

func rk4(model Model, y []float64, multiplier float64) []float64 {
	const h = .25
	k1 := model.rate(y, multiplier)
	state := make([]float64, len(y))
	for i, a := range y {
		state[i] = a + (h/2)*k1[i]
	}
	k2 := model.rate(state, multiplier)
	for i, a := range y {
		state[i] = a + (h/2)*k2[i]
	}
	k3 := model.rate(state, multiplier)
	for i, a := range y {
		state[i] = a + h*k3[i]
	}
	k4 := model.rate(state, multiplier)
	for i, a := range y {
		state[i] = a + (h/6)*(((k1[i]+2*k2[i])+2*k3[i])+k4[i])
	}
	return state
}
func simulate(model Model, y, multipliers []float64) [][]float64 {
	y = append([]float64(nil), y...)
	out := make([][]float64, len(multipliers))
	inflows := model.inflowIndices()
	for d, m := range multipliers {
		for _, i := range inflows {
			y[i] = 0
		}
		for step := 0; step < 4; step++ {
			y = rk4(model, y, m)
		}
		out[d] = append([]float64(nil), y...)
	}
	return out
}

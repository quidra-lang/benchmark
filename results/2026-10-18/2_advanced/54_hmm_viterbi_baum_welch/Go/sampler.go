package main

type Minstd struct{ State int64 }

func (r *Minstd) uniform() float64 {
	r.State = 48271 * r.State % 2147483647
	return float64(r.State) / 2147483647
}
func draw(weights []float64, rng *Minstd) int {
	total := sum(weights)
	threshold := rng.uniform() * total
	cumulative := 0.0
	for i, w := range weights {
		cumulative += w
		if threshold < cumulative {
			return i
		}
	}
	return len(weights) - 1
}
func syntheticSequence(model *Model, length int, rng *Minstd) ([]int, []int) {
	states, observations := make([]int, length), make([]int, length)
	for t := 0; t < length; t++ {
		weights := model.Initial
		if t > 0 {
			weights = model.Transition[states[t-1]]
		}
		state := draw(weights, rng)
		symbol := draw(model.Emission[state], rng)
		states[t], observations[t] = state, symbol
	}
	return states, observations
}
func posteriorPath(model *Model, forward [][]float64, rng *Minstd) []int {
	path := make([]int, len(forward))
	path[len(path)-1] = draw(forward[len(path)-1], rng)
	for t := len(path) - 2; t >= 0; t-- {
		following := path[t+1]
		weights := make([]float64, len(model.States))
		for i := range weights {
			weights[i] = forward[t][i] * model.Transition[i][following]
		}
		path[t] = draw(weights, rng)
	}
	return path
}

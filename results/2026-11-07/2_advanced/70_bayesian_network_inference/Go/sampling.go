package main

type Generator struct{ State int64 }

func (g *Generator) next() float64 {
	g.State = 48271 * g.State % 2147483647
	return float64(g.State) / 2147483647
}
func selectState(probs []float64, u float64) int {
	c := 0.0
	for s, p := range probs {
		c += p
		if u < c {
			return s
		}
	}
	return len(probs) - 1
}
func (g *Generator) weightedSample(evidence []Evidence, topological []int, n Network) ([]int, float64) {
	observed := map[int]int{}
	for _, e := range evidence {
		observed[e.V] = e.S
	}
	a := make([]int, len(n.Variables))
	weight := 1.0
	for _, v := range topological {
		variable := n.Variables[v]
		row := parentCombination(variable.Parents,
			a, n)
		if state, found := observed[v]; found {
			a[v] = state
			weight *= variable.Theta[row][state]
		} else {
			a[v] = selectState(variable.Theta[row],
				g.next())
		}
	}
	return a, weight
}

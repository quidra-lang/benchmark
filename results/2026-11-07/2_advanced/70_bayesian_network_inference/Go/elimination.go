package main

type Step struct {
	V, Fill, Size int
	Scope         []int
}
type Plan struct {
	Steps             []Step
	Max, Total, Width int
}
type EliminationResult struct {
	Final      Factor
	Assignment []int
}

func contains(a []int, v int) bool {
	for _, x := range a {
		if x == v {
			return true
		}
	}
	return false
}
func plan(factors []Factor, elimination []int, method string, n Network) Plan {
	size := len(n.Variables)
	edges := make([][]bool,
		size)
	active := make([]bool, size)
	for i := range edges {
		edges[i] = make([]bool, size)
	}
	for _, f := range factors {
		for _, a := range f.Variables {
			active[a] = true
			for _, b := range f.Variables {
				if a != b {
					edges[a][b] = true
				}
			}
		}
	}
	remaining := map[int]bool{}
	for _, v := range elimination {
		remaining[v] = true
	}
	orderRank := map[int]int{}
	for i, v := range n.Settings.Order {
		orderRank[v] = i
	}
	result := Plan{}
	for len(remaining) > 0 {
		chosen,
			chosenFill, chosenDegree := -1, 0, 0
		var neighbors []int
		for v := 0; v < size; v++ {
			if !remaining[v] {
				continue
			}
			var ns []int
			for u := 0; u < size; u++ {
				if active[u] && edges[v][u] {
					ns = append(ns,
						u)
				}
			}
			fill := 0
			for i, a := range ns {
				for _, b := range ns[i+1:] {
					if !edges[a][b] {
						fill++
					}
				}
			}
			better := chosen < 0
			if !better {
				if method == "given" {
					better = orderRank[v] < orderRank[chosen]
				} else {
					better = fill < chosenFill || fill == chosenFill && (len(ns) < chosenDegree || len(ns) == chosenDegree && v < chosen)
				}
			}
			if better {
				chosen,
					chosenFill, chosenDegree, neighbors = v, fill, len(ns), ns
			}
		}
		scope := variableUnion([]int{chosen}, neighbors)
		entries := assignmentCount(scope,
			n)
		result.Steps = append(result.Steps, Step{chosen, chosenFill, entries, scope})
		result.Max = max(result.Max,
			entries)
		result.Total += entries
		result.Width = max(result.Width, len(scope)-1)
		for _, a := range neighbors {
			for _, b := range neighbors {
				if a != b {
					edges[a][b] = true
				}
			}
		}
		active[chosen] = false
		delete(remaining, chosen)
	}
	return result
}
func execute(initial []Factor, p Plan, maximum bool, evidence []Evidence, n Network) EliminationResult {
	factors := append([]Factor(nil),
		initial...)
	products := map[int]Factor{}
	for _, step := range p.Steps {
		var bucket, remaining []Factor
		for _, f := range factors {
			if contains(f.Variables, step.V) {
				bucket = append(bucket, f)
			} else {
				remaining = append(remaining,
					f)
			}
		}
		f := product(bucket, n)
		products[step.V] = f
		factors = append(remaining, eliminate(f, step.V, maximum,
			n))
	}
	result := EliminationResult{Final: product(factors, n)}
	if maximum {
		result.Assignment = make([]int,
			len(n.Variables))
		for _, e := range evidence {
			result.Assignment[e.V] = e.S
		}
		for i := len(p.Steps) - 1; i >= 0; i-- {
			v := p.Steps[i].V
			best := -1.0
			bestState := 0
			for state := range n.Variables[v].States {
				result.Assignment[v] = state
				value := products[v].value(result.Assignment,
					n)
				if value > best {
					best, bestState = value, state
				}
			}
			result.Assignment[v] = bestState
		}
	}
	return result
}

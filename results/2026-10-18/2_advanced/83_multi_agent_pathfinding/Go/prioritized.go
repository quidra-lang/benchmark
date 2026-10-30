package main

import "fmt"

func prioritized(g *Grid, p Parameters, order []int, number int, r *Run) ([][]int, int, int) {
	b := newProhibitions()
	paths := make([][]int, len(g.Agents))
	planned := 0
	for _, agent := range order {
		before := r.Counter.Expansions
		path := lowLevel(g, agent, g.Agents[agent].Start, 0, p.Horizon, b, false, &r.Counter)
		if r.Counter.Aborted {
			return nil, planned, agent
		}
		text := fmt.Sprintf("order %d agent %s", number, name(agent))
		if path == nil {
			r.Trace = append(r.Trace, fmt.Sprintf("%s failed expansions %d", text, r.Counter.Expansions-before))
			return nil, planned, agent
		}
		r.Trace = append(r.Trace, fmt.Sprintf("%s cost %d expansions %d", text, len(path)-1, r.Counter.Expansions-before))
		paths[agent] = path
		planned++
		b.Reserve(path, 0, true)
	}
	return paths, planned, -1
}

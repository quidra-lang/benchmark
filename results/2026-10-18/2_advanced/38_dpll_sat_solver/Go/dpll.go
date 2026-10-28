package main

import "fmt"

type SearchStats struct{ Decisions, Propagations, Conflicts, MaxDepth int }

func (s *SearchStats) Add(other SearchStats) {
	s.Decisions += other.Decisions
	s.Propagations += other.Propagations
	s.Conflicts += other.Conflicts
	s.MaxDepth = max(s.MaxDepth, other.MaxDepth)
}

type TrailEntry struct {
	Literal int
	Kind    byte
}

func runRound(variables int, received [][]int) ([]bool, []string, SearchStats) {
	clauses := make([][]int, len(received))
	for i, c := range received {
		clauses[i] = append([]int(nil), c...)
	}
	assignment := make([]int, variables+1)
	watches := map[int][]int{}
	trail := []TrailEntry{}
	queueHead := 0
	trace := []string{}
	stats := SearchStats{}
	value := func(literal int) int {
		v := assignment[abs(literal)]
		if literal < 0 {
			return -v
		}
		return v
	}
	assign := func(literal int, kind byte) {
		v := 1
		if literal < 0 {
			v = -1
		}
		assignment[abs(literal)] = v
		trail = append(trail, TrailEntry{literal, kind})
		trace = append(trace, fmt.Sprintf("%c%d", kind, literal))
	}
	conflict := func() { stats.Conflicts++; trace = append(trace, "C") }
	for i, c := range clauses {
		if len(c) >= 2 {
			watches[c[0]] = append(watches[c[0]], i)
			watches[c[1]] = append(watches[c[1]], i)
		}
	}
	for _, c := range clauses {
		if len(c) == 0 {
			conflict()
			return nil, trace, stats
		}
		if len(c) == 1 {
			literal := c[0]
			truth := value(literal)
			if truth < 0 {
				conflict()
				return nil, trace, stats
			}
			if truth == 0 {
				assign(literal, 'P')
				stats.Propagations++
			}
		}
	}
	for {
		foundConflict := false
		for queueHead < len(trail) {
			falseLiteral := -trail[queueHead].Literal
			queueHead++
			watchList := watches[falseLiteral]
			index := 0
			for index < len(watchList) {
				id := watchList[index]
				c := clauses[id]
				if c[0] == falseLiteral {
					c[0], c[1] = c[1], c[0]
				}
				other := c[0]
				if value(other) > 0 {
					index++
					continue
				}
				substitute := -1
				for j := 2; j < len(c); j++ {
					if value(c[j]) >= 0 {
						substitute = j
						break
					}
				}
				if substitute >= 0 {
					c[1], c[substitute] = c[substitute], c[1]
					watchList = append(watchList[:index], watchList[index+1:]...)
					watches[falseLiteral] = watchList
					watches[c[1]] = append(watches[c[1]], id)
					continue
				}
				truth := value(other)
				if truth < 0 {
					conflict()
					foundConflict = true
					break
				}
				if truth == 0 {
					assign(other, 'P')
					stats.Propagations++
				}
				index++
			}
			if foundConflict {
				break
			}
		}
		if foundConflict {
			for len(trail) > 0 && trail[len(trail)-1].Kind != 'D' {
				entry := trail[len(trail)-1]
				trail = trail[:len(trail)-1]
				assignment[abs(entry.Literal)] = 0
			}
			if len(trail) == 0 {
				return nil, trace, stats
			}
			decision := trail[len(trail)-1].Literal
			trail = trail[:len(trail)-1]
			assignment[abs(decision)] = 0
			assign(-decision, 'F')
			queueHead = len(trail) - 1
			continue
		}
		counts := map[int]int{}
		for _, c := range clauses {
			satisfied := false
			for _, lit := range c {
				if value(lit) > 0 {
					satisfied = true
					break
				}
			}
			if satisfied {
				continue
			}
			for _, lit := range c {
				if value(lit) == 0 {
					counts[lit]++
				}
			}
		}
		if len(counts) == 0 {
			model := make([]bool, variables+1)
			for v := 1; v <= variables; v++ {
				model[v] = assignment[v] > 0
			}
			return model, trace, stats
		}
		best := 0
		for lit, count := range counts {
			if best == 0 || count > counts[best] || count == counts[best] && (abs(lit) < abs(best) || abs(lit) == abs(best) && lit > best) {
				best = lit
			}
		}
		assign(best, 'D')
		stats.Decisions++
		depth := 0
		for _, entry := range trail {
			if entry.Kind == 'D' || entry.Kind == 'F' {
				depth++
			}
		}
		stats.MaxDepth = max(stats.MaxDepth, depth)
	}
}

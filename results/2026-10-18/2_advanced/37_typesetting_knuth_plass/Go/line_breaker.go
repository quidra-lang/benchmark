package main

func lineClass(slack int, last bool) int {
	if last {
		return 1
	}
	if slack <= 1 {
		return 0
	}
	if slack <= 3 {
		return 1
	}
	if slack <= 6 {
		return 2
	}
	return 3
}
func lineCost(m *TextMetrics, start, end, previousClass int, p map[string]int) int {
	slack := m.Slack(start, end)
	last := end == m.End
	current := lineClass(slack, last)
	cost := p["line_penalty"]
	if slack < 0 {
		cost += p["overfull_penalty"]
	} else if !last {
		cost += slack * slack
	}
	if m.Breaks[end].Midword {
		cost += p["hyphen_penalty"]
		if m.Breaks[start].Midword {
			cost += p["double_hyphen_demerit"]
		}
	}
	if last && m.Breaks[start].Midword {
		cost += p["final_hyphen_demerit"]
	}
	if abs(current-previousClass) >= 2 {
		cost += p["fitness_demerit"]
	}
	return cost
}
func breakingCost(m *TextMetrics, breaking []int, p map[string]int) int {
	total, previous, previousClass := 0, 0, 1
	for _, end := range breaking {
		total += lineCost(m, previous, end, previousClass, p)
		previousClass = lineClass(m.Slack(previous, end), end == m.End)
		previous = end
	}
	return total
}

type BreakState struct{ Cost, Start, PreviousClass int }

func knuthPlass(m *TextMetrics, p map[string]int) ([]int, int) {
	states := make([][4]*BreakState, m.End+1)
	states[0][1] = &BreakState{}
	for end := 1; end <= m.End; end++ {
		for start := end - 1; start >= 0; start-- {
			slack := m.Slack(start, end)
			if slack < 0 && end != start+1 {
				break
			}
			current := lineClass(slack, end == m.End)
			for previousClass, previous := range states[start] {
				if previous == nil {
					continue
				}
				cost := previous.Cost + lineCost(m, start, end, previousClass, p)
				best := states[end][current]
				if best == nil || cost < best.Cost || cost == best.Cost && (start < best.Start || start == best.Start && previousClass < best.PreviousClass) {
					states[end][current] = &BreakState{cost, start, previousClass}
				}
			}
		}
	}
	breaking := []int{}
	position, current := m.End, 1
	cost := states[position][current].Cost
	for position > 0 {
		breaking = append(breaking, position)
		state := states[position][current]
		position, current = state.Start, state.PreviousClass
	}
	for i, j := 0, len(breaking)-1; i < j; i, j = i+1, j-1 {
		breaking[i], breaking[j] = breaking[j], breaking[i]
	}
	return breaking, cost
}
func greedyBreaking(m *TextMetrics, p map[string]int) ([]int, int) {
	breaking := []int{}
	for start := 0; start < m.End; {
		chosen := start + 1
		if m.Slack(start, chosen) >= 0 {
			for end := chosen + 1; end <= m.End; end++ {
				if m.Slack(start, end) < 0 {
					break
				}
				chosen = end
			}
		}
		breaking = append(breaking, chosen)
		start = chosen
	}
	return breaking, breakingCost(m, breaking, p)
}
func breakText(m *TextMetrics, method string, p map[string]int) ([]int, int) {
	if method == "kp" {
		return knuthPlass(m, p)
	}
	return greedyBreaking(m, p)
}

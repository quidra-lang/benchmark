package main

func floorDiv(a, b int64) int64 {
	q := a / b
	if a%b < 0 {
		q--
	}
	return q
}
func abs(a int64) int64 {
	if a < 0 {
		return -a
	}
	return a
}
func firstMax(values [4]int64) int {
	best := 0
	for a := 1; a < 4; a++ {
		if values[a] > values[best] {
			best = a
		}
	}
	return best
}
func rowMax(values [4]int64) int64 { return values[firstMax(values)] }
func bellman(e *Environment, values []int64, gamma int64, state, action int) int64 {
	var total int64
	for _, t := range e.Transitions[state][action] {
		var future int64
		if target := e.World.StateIndex[t.Cell]; target >= 0 {
			future = floorDiv(gamma*values[target], 100)
		}
		total += t.Numerator * (10000*e.Reward(t.Cell) + future)
	}
	return floorDiv(total, e.SlipTotal)
}
func actionValues(e *Environment, values []int64, gamma int64, state int) [4]int64 {
	var row [4]int64
	for a := range 4 {
		row[a] = bellman(e, values, gamma, state, a)
	}
	return row
}
func greedyPolicy(e *Environment, values []int64, gamma int64) []int {
	policy := make([]int, len(values))
	for s := range policy {
		policy[s] = firstMax(actionValues(e, values, gamma, s))
	}
	return policy
}
func valueIteration(e *Environment, gamma, theta int64) ([]int64, []int64) {
	values := make([]int64, len(e.World.States))
	changes := []int64{}
	for {
		updated := make([]int64, len(values))
		var delta int64
		for s, old := range values {
			updated[s] = rowMax(actionValues(e, values, gamma, s))
			delta = max(delta, abs(updated[s]-old))
		}
		changes = append(changes, delta)
		values = updated
		if delta <= theta {
			return values, changes
		}
	}
}
func inPlaceValueIteration(e *Environment, gamma, theta int64) ([]int64, int) {
	values := make([]int64, len(e.World.States))
	for sweep := 1; ; sweep++ {
		var delta int64
		for s := range values {
			v := rowMax(actionValues(e, values, gamma, s))
			delta = max(delta, abs(v-values[s]))
			values[s] = v
		}
		if delta <= theta {
			return values, sweep
		}
	}
}
func evaluatePolicy(e *Environment, policy []int, initial []int64, gamma, theta int64) ([]int64, int) {
	values := append([]int64(nil), initial...)
	for sweep := 1; ; sweep++ {
		var delta int64
		for s, a := range policy {
			v := bellman(e, values, gamma, s, a)
			delta = max(delta, abs(v-values[s]))
			values[s] = v
		}
		if delta <= theta {
			return values, sweep
		}
	}
}

type PolicyRound struct {
	Sweeps, Changes int
	StartValue      int64
}

func policyIteration(e *Environment, gamma, theta int64) ([]int, []int64, []PolicyRound) {
	policy := make([]int, len(e.World.States))
	values := make([]int64, len(policy))
	rounds := []PolicyRound{}
	for {
		v, sweeps := evaluatePolicy(e, policy, values, gamma, theta)
		values = v
		improved := greedyPolicy(e, values, gamma)
		changes := 0
		for s, a := range policy {
			if improved[s] != a {
				changes++
			}
		}
		rounds = append(rounds, PolicyRound{sweeps, changes, values[e.World.StartState]})
		policy = improved
		if changes == 0 {
			return policy, values, rounds
		}
	}
}

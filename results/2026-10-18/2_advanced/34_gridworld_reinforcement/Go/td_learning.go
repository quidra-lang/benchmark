package main

func choose(g *RandomGenerator, row [4]int64, epsilon int64) int {
	if g.Draw()%1000 < epsilon {
		return int(g.Draw() % 4)
	}
	return firstMax(row)
}
func tdTarget(reward int64, terminal bool, next, gamma int64) int64 {
	if terminal {
		return 10000 * reward
	}
	return 10000*reward + floorDiv(gamma*next, 100)
}
func expectedValue(row [4]int64, epsilon int64) int64 {
	var total int64
	for _, v := range row {
		total += v
	}
	return floorDiv(epsilon*total+4*(1000-epsilon)*rowMax(row), 4000)
}
func tdUpdate(row *[4]int64, action int, target, alpha int64) {
	row[action] += floorDiv(alpha*(target-row[action]), 100)
}

type ModelOutcome struct {
	Reward int64
	Next   int
}
type DynaModel struct {
	Outcomes [][4]*ModelOutcome
	Pairs    [][2]int
}

func newDynaModel(n int) *DynaModel { return &DynaModel{Outcomes: make([][4]*ModelOutcome, n)} }
func (m *DynaModel) Record(state, action int, reward int64, next int) {
	if m.Outcomes[state][action] == nil {
		m.Pairs = append(m.Pairs, [2]int{state, action})
	}
	m.Outcomes[state][action] = &ModelOutcome{reward, next}
}
func (m *DynaModel) Plan(g *RandomGenerator, q [][4]int64, gamma, alpha int64, count int) {
	for range count {
		pair := m.Pairs[int(g.Draw()%int64(len(m.Pairs)))]
		state, action := pair[0], pair[1]
		outcome := m.Outcomes[state][action]
		var next int64
		if outcome.Next >= 0 {
			next = rowMax(q[outcome.Next])
		}
		tdUpdate(&q[state], action, tdTarget(outcome.Reward, outcome.Next < 0, next, gamma), alpha)
	}
}

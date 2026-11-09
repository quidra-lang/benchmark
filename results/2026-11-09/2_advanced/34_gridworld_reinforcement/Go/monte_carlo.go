package main

func discountedReturn(rewards []int64, gamma int64) int64 {
	var value int64
	for i := len(rewards) - 1; i >= 0; i-- {
		value = 10000*rewards[i] + floorDiv(gamma*value, 100)
	}
	return value
}

type HistoryStep struct {
	State, Action int
	Reward        int64
}
type ReturnAverages struct{ Sums, Counts [][4]int64 }

func newReturnAverages(n int) *ReturnAverages {
	return &ReturnAverages{make([][4]int64, n), make([][4]int64, n)}
}
func (a *ReturnAverages) Update(q [][4]int64, history []HistoryStep, gamma int64) {
	seen := map[[2]int]bool{}
	first := make([]bool, len(history))
	for i, h := range history {
		key := [2]int{h.State, h.Action}
		first[i] = !seen[key]
		seen[key] = true
	}
	var value int64
	for i := len(history) - 1; i >= 0; i-- {
		h := history[i]
		value = 10000*h.Reward + floorDiv(gamma*value, 100)
		if first[i] {
			a.Sums[h.State][h.Action] += value
			a.Counts[h.State][h.Action]++
			q[h.State][h.Action] = floorDiv(a.Sums[h.State][h.Action], a.Counts[h.State][h.Action])
		}
	}
}
